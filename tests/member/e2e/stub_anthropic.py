#!/usr/bin/env python3
# stub_anthropic.py (harbor#1278) - a stand-in Messages API for sim-linux.sh, so the real Claude Code CLI runs a real session with no account.
# Each model turn pops one line of QUEUE (a JSON {"name","input"}: a tool call, or {"text": "..."}) and streams it back; with the queue empty it
# ends the turn with a short text. Every request body is appended to LOG (one JSON per line), so a run can show what Claude Code sent.
#   python3 stub_anthropic.py <port> <queue file> <log file>
import json, sys, http.server, threading
PORT, QUEUE, LOG = int(sys.argv[1]), sys.argv[2], sys.argv[3]
LOCK = threading.Lock()
N = [0]

def pop():
    with LOCK:
        try:
            lines = [l for l in open(QUEUE).read().splitlines() if l.strip()]
        except OSError:
            lines = []
        if not lines:
            return {"text": "stub: the queue is empty"}
        open(QUEUE, "w").write("\n".join(lines[1:]) + ("\n" if lines[1:] else ""))
        return json.loads(lines[0])

def sse(ev, data):
    return ("event: %s\ndata: %s\n\n" % (ev, json.dumps(data))).encode()

class H(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"
    def log_message(self, *a): pass
    def do_GET(self):
        self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers(); self.wfile.write(b"{}")
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length") or 0))
        try: req = json.loads(body)
        except ValueError: req = {}
        with LOCK:
            open(LOG, "a").write(json.dumps({"path": self.path, "req": req}) + "\n")
        if not self.path.startswith("/v1/messages") or self.path.startswith("/v1/messages/count_tokens"):
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
            self.wfile.write(json.dumps({"input_tokens": 10}).encode()); return
        model = req.get("model", "claude-opus-5-5")
        small = "haiku" in model
        step = {"text": "stub"} if small else pop()
        N[0] += 1
        mid = "msg_stub%d" % N[0]
        blocks = []
        if "text" in step:
            blocks.append({"type": "text", "text": step["text"]}); stop = "end_turn"
        else:
            blocks.append({"type": "tool_use", "id": "toolu_stub%d" % N[0], "name": step["name"], "input": {}}); stop = "tool_use"
        usage = {"input_tokens": 10, "output_tokens": 5}
        if not req.get("stream"):
            c = [dict(b, input=step.get("input", {})) if b["type"] == "tool_use" else b for b in blocks]
            self.send_response(200); self.send_header("Content-Type", "application/json"); self.end_headers()
            self.wfile.write(json.dumps({"id": mid, "type": "message", "role": "assistant", "model": model, "content": c, "stop_reason": stop, "stop_sequence": None, "usage": usage}).encode()); return
        self.send_response(200); self.send_header("Content-Type", "text/event-stream"); self.end_headers()
        w = self.wfile.write
        w(sse("message_start", {"type": "message_start", "message": {"id": mid, "type": "message", "role": "assistant", "model": model, "content": [], "stop_reason": None, "stop_sequence": None, "usage": usage}}))
        for i, b in enumerate(blocks):
            if b["type"] == "text":
                w(sse("content_block_start", {"type": "content_block_start", "index": i, "content_block": {"type": "text", "text": ""}}))
                w(sse("content_block_delta", {"type": "content_block_delta", "index": i, "delta": {"type": "text_delta", "text": b["text"]}}))
            else:
                w(sse("content_block_start", {"type": "content_block_start", "index": i, "content_block": dict(b)}))
                w(sse("content_block_delta", {"type": "content_block_delta", "index": i, "delta": {"type": "input_json_delta", "partial_json": json.dumps(step.get("input", {}))}}))
            w(sse("content_block_stop", {"type": "content_block_stop", "index": i}))
        w(sse("message_delta", {"type": "message_delta", "delta": {"stop_reason": stop, "stop_sequence": None}, "usage": {"output_tokens": 5}}))
        w(sse("message_stop", {"type": "message_stop"}))

http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
