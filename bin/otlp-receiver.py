#!/usr/bin/env python3
"""otlp-receiver.py (harbor#1181 lane 5b) — Claude Code's own telemetry, into the collector's store.
INTERPRETER EXCEPTION: python3, because an HTTP listener is not a shell job; stdlib only, run with python3 -I.

  python3 -I bin/otlp-receiver.py [--port 4318] [--store DIR]     serve until killed (launchd keeps it alive)
  python3 -I bin/otlp-receiver.py --ingest FILE [--store DIR]     one OTLP/JSON logs body from a file (tests)

Accepts OTLP/HTTP JSON on 127.0.0.1 only: POST /v1/logs. Each record keeps its event name and an ALLOWLIST of
attributes (session, tool, decision, cost, tokens, model, hook and compaction counts); prompt text, tool input and
anything unknown is dropped, whatever the client was configured to send. Records land in <store>/cc/<UTC day>.jsonl;
<store>/cc-summary.json (world-readable) counts events per day per name, for collector-check's cross-check against
the guard ledger. It is the client's own record, emitted by Claude Code and not by a hook a session can edit; a
local process can still POST here, so it evidences silence, never authenticity.
"""
import argparse, json, os, sys, threading
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

KEEP = {"event.name", "session.id", "prompt.id", "tool_name", "tool_use_id", "decision", "decision_type",
        "decision_source", "source", "success", "duration_ms", "model", "cost_usd", "input_tokens", "output_tokens",
        "cache_read_tokens", "cache_creation_tokens", "query_source", "agent_type", "total_tokens",
        "total_tool_uses", "hook_event", "num_blocking", "trigger", "pre_tokens", "post_tokens",
        "transcripts_deleted", "result", "from_mode", "to_mode", "error_count"}
MAX_BODY = 5 * 1024 * 1024
LOCK = threading.Lock()


def value(v):
    for k in ("stringValue", "boolValue", "intValue", "doubleValue"):
        if k in v:
            return v[k]
    return None


def records(body):
    for rl in body.get("resourceLogs", []) or []:
        for sl in rl.get("scopeLogs", []) or []:
            for r in sl.get("logRecords", []) or []:
                yield r


def ingest(body, store):
    """Writes the allowlisted part of every record; returns how many were kept."""
    cc = os.path.join(store, "cc"); os.makedirs(cc, mode=0o700, exist_ok=True)
    n = 0; per_day = {}; cost = {}
    for r in records(body):
        attrs = {a.get("key"): value(a.get("value", {})) for a in r.get("attributes", []) or [] if isinstance(a, dict)}
        name = attrs.get("event.name") or (value(r.get("body", {})) if isinstance(r.get("body"), dict) else None)
        if not isinstance(name, str) or not name:
            continue
        try:
            ns = int(r.get("timeUnixNano") or r.get("observedTimeUnixNano") or 0)
        except (TypeError, ValueError):
            ns = 0
        t = datetime.fromtimestamp(ns / 1e9, timezone.utc) if ns else datetime.now(timezone.utc)
        kept = {k: v for k, v in attrs.items() if k in KEEP and k != "event.name"}
        line = json.dumps({"ts": t.strftime("%Y-%m-%dT%H:%M:%SZ"), "event": name, "attrs": kept},
                          sort_keys=True, separators=(",", ":"))
        day = t.strftime("%Y-%m-%d")
        per_day.setdefault(day, []).append((name, line)); n += 1
        # the client prices its own API calls: cost per session is what tells spend per PR, in dollars
        if name.endswith("api_request") and isinstance(kept.get("session.id"), str):
            try:
                cost[kept["session.id"]] = cost.get(kept["session.id"], 0.0) + float(kept.get("cost_usd") or 0)
            except (TypeError, ValueError):
                pass
    with LOCK:
        for day, rows in per_day.items():
            with open(os.path.join(cc, f"{day}.jsonl"), "a", encoding="utf-8") as f:
                f.write("".join(l + "\n" for _, l in rows))
        summ = os.path.join(store, "cc-summary.json")   # beside status.json: the store is 0755, cc/ is not
        try:
            s = json.load(open(summ, encoding="utf-8"))
        except (OSError, ValueError):
            s = {}
        for day, rows in per_day.items():
            d = s.setdefault(day, {})
            for name, _ in rows:
                d[name] = d.get(name, 0) + 1
        c = s.setdefault("cost_usd_by_session", {})
        for sid, usd in cost.items():
            c[sid] = round(c.get(sid, 0.0) + usd, 6)
        tmp = summ + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(s, f, sort_keys=True)
        os.chmod(tmp, 0o644); os.replace(tmp, summ)
    return n


class Handler(BaseHTTPRequestHandler):
    store = ""

    def log_message(self, *a):   # one line per request on stderr would be the census; the store is the record
        pass

    def reply(self, code, obj):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)

    def do_POST(self):
        if self.path not in ("/v1/logs", "/v1/metrics", "/v1/traces"):
            return self.reply(404, {"error": "not an OTLP path"})
        if "json" not in (self.headers.get("Content-Type") or ""):
            return self.reply(415, {"error": "OTLP/HTTP JSON only: set OTEL_EXPORTER_OTLP_PROTOCOL=http/json"})
        n = int(self.headers.get("Content-Length") or 0)
        if n <= 0 or n > MAX_BODY:
            return self.reply(413, {"error": "empty or over 5 MB"})
        try:
            body = json.loads(self.rfile.read(n))
        except ValueError:
            return self.reply(400, {"error": "not JSON"})
        if self.path == "/v1/logs" and isinstance(body, dict):
            ingest(body, self.store)
        return self.reply(200, {})   # metrics and traces are accepted and dropped: logs carry what is cross-checked


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--port", type=int, default=4318)
    ap.add_argument("--store", default=os.environ.get("HARBOR_COLLECTOR_STORE", "/Library/Application Support/Harbor/collector"))
    ap.add_argument("--ingest")
    a = ap.parse_args()
    if a.ingest:
        print(ingest(json.load(open(a.ingest, encoding="utf-8")), a.store)); return
    Handler.store = a.store
    os.umask(0o077)
    ThreadingHTTPServer(("127.0.0.1", a.port), Handler).serve_forever()


if __name__ == "__main__":
    main()
