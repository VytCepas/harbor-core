#!/usr/bin/env python3
# sim_github.py (harbor#1278) — github.com and api.github.com for sim-linux.sh, over real TLS on 127.0.0.1:443 inside its container.
"""
  python3 sim_github.py <board-state> <git-root> <download-dir> <cert> <key>

The container's /etc/hosts sends both names here and its system store trusts the cert's CA, so the floor's own curl and git run unchanged.
  api.github.com            tests/hub/fixtures/stub_board.py's Board, unchanged: the board and its control files live in <board-state>
  github.com/<o>/<r>.git/*  git http-backend over <git-root>: the hub repo and harbor-core
  github.com/<o>/<r>/releases/download/<v>/<file>   <download-dir>/<file>, or 404
Every request is one line in <board-state>/access.jsonl: host, method, path, and whether it carried an Authorization header (never its value).
"""
import json
import os
import re
import ssl
import subprocess
import sys
import threading
from http.server import ThreadingHTTPServer

BOARD_STATE, GIT_ROOT, DL_DIR, CERT, KEY = sys.argv[1:6]
STUB = os.path.join(os.path.dirname(os.path.abspath(__file__)), "stub_board.py")

# stub_board.py starts its own server at the end of the file; everything above that line is the Board class and its helpers.
_src = open(STUB).read()
_src = _src[: _src.rstrip().rfind("\nmain()")]
sys.argv = [STUB, BOARD_STATE, str(os.getpid())]
_ns = {"__name__": "stub_board", "__file__": STUB}
exec(compile(_src, STUB, "exec"), _ns)
Board = _ns["Board"]
LOG_LOCK = threading.Lock()


def note(handler, host):
    with LOG_LOCK, open(os.path.join(BOARD_STATE, "access.jsonl"), "a") as f:
        f.write(json.dumps({"host": host, "method": handler.command, "path": handler.path,
                            "auth": bool(handler.headers.get("Authorization"))}) + "\n")


def read_body(handler):
    if handler.headers.get("Transfer-Encoding", "").lower() == "chunked":
        out = b""
        while True:
            size = int(handler.rfile.readline().strip() or b"0", 16)
            if size == 0:
                handler.rfile.readline()
                return out
            out += handler.rfile.read(size)
            handler.rfile.readline()
    length = int(handler.headers.get("Content-Length") or 0)
    return handler.rfile.read(length) if length else b""


class Hub(Board):
    def plain(self, status, body=b"", ctype="text/plain"):
        self.send_response_only(status)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def git(self, path, query):
        body = read_body(self)
        env = {"PATH": "/usr/bin:/bin", "GIT_PROJECT_ROOT": GIT_ROOT, "GIT_HTTP_EXPORT_ALL": "1", "PATH_INFO": path,
               "QUERY_STRING": query, "REQUEST_METHOD": self.command, "CONTENT_TYPE": self.headers.get("Content-Type", ""),
               "CONTENT_LENGTH": str(len(body)), "REMOTE_ADDR": "127.0.0.1"}
        for name in ("Git-Protocol", "Content-Encoding"):
            if self.headers.get(name):
                env["HTTP_" + name.upper().replace("-", "_")] = self.headers[name]
        if self.headers.get("Git-Protocol"):
            env["GIT_PROTOCOL"] = self.headers["Git-Protocol"]
        out = subprocess.run(["git", "http-backend"], input=body, env=env, capture_output=True).stdout
        head, _, rest = out.partition(b"\r\n\r\n")
        if not _:
            head, _, rest = out.partition(b"\n\n")
        status, headers = 200, []
        for line in head.decode("latin-1").splitlines():
            k, _, v = line.partition(":")
            if k.lower() == "status":
                status = int(v.strip().split()[0])
            elif k:
                headers.append((k, v.strip()))
        self.send_response_only(status)
        for k, v in headers:
            self.send_header(k, v)
        self.send_header("Content-Length", str(len(rest)))
        self.end_headers()
        self.wfile.write(rest)

    def handle_any(self):
        host = (self.headers.get("Host") or "").split(":")[0]
        note(self, host)
        if host == "api.github.com":
            return Board.handle_any(self)
        if host != "github.com":
            return self.plain(404, b"unknown host")
        path, _, query = self.path.partition("?")
        if re.match(r"^/[^/]+/[^/]+\.git/", path):
            return self.git(path, query)
        m = re.match(r"^/[^/]+/[^/]+/releases/download/[^/]+/([A-Za-z0-9._-]+)$", path)
        if m and os.path.isfile(os.path.join(DL_DIR, m.group(1))):
            with open(os.path.join(DL_DIR, m.group(1)), "rb") as f:
                return self.plain(200, f.read(), "application/octet-stream")
        return self.plain(404, b"Not Found")

    do_GET = do_POST = do_PATCH = handle_any


def main():
    for name in ("issues", "comments", "perm"):
        os.makedirs(os.path.join(BOARD_STATE, name), exist_ok=True)
    server = ThreadingHTTPServer(("127.0.0.1", 443), Hub)
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(CERT, KEY)
    server.socket = ctx.wrap_socket(server.socket, server_side=True)
    open(os.path.join(BOARD_STATE, "up"), "w").close()
    server.serve_forever()


main()
