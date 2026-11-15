#!/usr/bin/env python3
"""stub_board.py (harbor#1278): a local stand-in for the GitHub REST calls the hub board makes. No real GitHub in tests.

  python3 stub_board.py <state-dir> <parent-pid>

Writes the port to <state-dir>/port, and reuses a port already there, so a restart answers at the same address. Writes up.<pid> once it listens. Issues are <state>/issues/<n>.json and comments <state>/comments/<n>.json, so a test seeds
or edits them with jq. Control files in <state>:
  token            the bearer token accepted; anything else gets 401
  date             the Date header, RFC 1123, and the clock for created_at; absent means now
  nodate           send no Date header
  expires          the github-authentication-token-expiration header
  remaining0       every reply says x-ratelimit-remaining: 0
  force            a status every call gets
  force-post       a status every POST gets
  perm/<login>     "<status> <permission>", or "<status> limited" for a rate-limited refusal; perm-default the same
Every request is one JSON line in <state>/log.jsonl: method, path, body, auth.
"""
import json
import os
import re
import sys
import threading
import time
from datetime import datetime, timezone
from email.utils import formatdate, parsedate_to_datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

STATE = sys.argv[1]
PARENT = int(sys.argv[2])
LOCK = threading.Lock()


def path(*parts):
    return os.path.join(STATE, *parts)


def read(name):
    try:
        with open(path(name)) as f:
            return f.read().strip()
    except OSError:
        return None


def load(*parts):
    with open(path(*parts)) as f:
        return json.load(f)


def save(value, *parts):
    with open(path(*parts), "w") as f:
        json.dump(value, f)


def now_iso():
    date = read("date")
    moment = parsedate_to_datetime(date) if date else datetime.now(timezone.utc)
    return moment.strftime("%Y-%m-%dT%H:%M:%SZ")


def next_id(name):
    value = int(read(name) or "0") + 1
    with open(path(name), "w") as f:
        f.write(str(value))
    return value


class Board(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *args):
        pass

    def reply(self, status, value, extra=None):
        body = json.dumps(value).encode()
        self.send_response_only(status)
        if not os.path.exists(path("nodate")):
            self.send_header("Date", read("date") or formatdate(usegmt=True))
        expires = read("expires")
        if expires:
            self.send_header("github-authentication-token-expiration", expires)
        if os.path.exists(path("remaining0")):
            self.send_header("x-ratelimit-remaining", "0")
        for key, val in (extra or {}).items():
            self.send_header(key, val)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def handle_any(self):
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length).decode() if length else ""
        auth = self.headers.get("Authorization") or ""
        with LOCK:
            with open(path("log.jsonl"), "a") as f:
                f.write(json.dumps({"method": self.command, "path": self.path, "body": raw, "auth": auth}) + "\n")
            self.route(raw, auth)

    def route(self, raw, auth):
        if auth != "Bearer " + (read("token") or ""):
            return self.reply(401, {"message": "Bad credentials"})
        forced = read("force") or (read("force-post") if self.command == "POST" else None)
        if forced:
            return self.reply(int(forced), {"message": "forced"})
        url, _, query = self.path.partition("?")
        args = dict(p.split("=", 1) for p in query.split("&") if "=" in p)
        m = re.fullmatch(r"/repos/[^/]+/[^/]+/(.+)", url)
        rest = m.group(1) if m else ""
        data = json.loads(raw) if raw else {}
        if rest == "issues":
            return self.create_issue(data) if self.command == "POST" else self.list_issues(args)
        m = re.fullmatch(r"issues/(\d+)", rest)
        if m:
            return self.one_issue(m.group(1), data)
        m = re.fullmatch(r"issues/(\d+)/comments", rest)
        if m:
            return self.comments(m.group(1), data, args)
        m = re.fullmatch(r"collaborators/([^/]+)/permission", rest)
        if m:
            return self.permission(m.group(1))
        return self.reply(404, {"message": "Not Found"})

    def create_issue(self, data):
        number = next_id("next-issue")
        # labels and assignees from a Read role are dropped silently, as GitHub does (R18).
        issue = {"number": number, "title": data.get("title"), "body": data.get("body"), "state": "open",
                 "user": {"login": read("login") or "alice", "type": "User"}, "created_at": now_iso()}
        save(issue, "issues", f"{number}.json")
        save([], "comments", f"{number}.json")
        self.reply(201, issue)

    def list_issues(self, args):
        names = [n for n in os.listdir(path("issues")) if n.endswith(".json")]
        issues = [load("issues", n) for n in names]
        issues.sort(key=lambda i: i["number"], reverse=args.get("direction") != "asc")
        if args.get("creator"):
            issues = [i for i in issues if i["user"]["login"].lower() == args["creator"].lower()]
        if args.get("state", "open") != "all":
            issues = [i for i in issues if i["state"] == args.get("state", "open")]
        self.reply(200, issues[: int(args.get("per_page", 30))])

    def one_issue(self, number, data):
        if not os.path.exists(path("issues", f"{number}.json")):
            return self.reply(404, {"message": "Not Found"})
        issue = load("issues", f"{number}.json")
        if self.command == "PATCH":
            issue.update(data)
            save(issue, "issues", f"{number}.json")
        self.reply(200, issue)

    def comments(self, number, data, args):
        if not os.path.exists(path("comments", f"{number}.json")):
            return self.reply(404, {"message": "Not Found"})
        items = load("comments", f"{number}.json")
        if self.command == "POST":
            stamp = now_iso()
            item = {"id": next_id("next-comment") + 9000, "body": data.get("body"), "created_at": stamp, "updated_at": stamp,
                    "user": {"login": read("login") or "alice", "type": "User"}}
            items.append(item)
            save(items, "comments", f"{number}.json")
            return self.reply(201, item)
        size = int(args.get("per_page", 30))
        page = int(args.get("page", 1))
        self.reply(200, items[(page - 1) * size: page * size])

    def permission(self, login):
        answer = read(os.path.join("perm", login)) or read("perm-default") or "200 write"
        status, _, value = answer.partition(" ")
        if value == "limited":
            return self.reply(int(status), {"message": "API rate limit exceeded"}, {"x-ratelimit-remaining": "0"})
        if status != "200":
            return self.reply(int(status), {"message": "refused"})
        self.reply(200, {"permission": value, "user": {"login": login}})

    do_GET = do_POST = do_PATCH = handle_any


def main():
    for name in ("issues", "comments", "perm"):
        os.makedirs(path(name), exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", int(read("port") or 0)), Board)
    with open(path("port.tmp"), "w") as f:
        f.write(str(server.server_address[1]))
    os.rename(path("port.tmp"), path("port"))
    with open(path(f"up.{os.getpid()}"), "w") as f:
        f.write("")
    threading.Thread(target=server.serve_forever, daemon=True).start()
    while True:  # a suite that dies must not leave this running
        time.sleep(1)
        try:
            os.kill(PARENT, 0)
        except OSError:
            return


main()
