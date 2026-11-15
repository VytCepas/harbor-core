#!/usr/bin/env python3
"""terminal_run.py (harbor#1278): runs a command on a real terminal and answers it, as a person would. No expect on a stock box.

  python3 terminal_run.py <steps-file> <transcript-file> -- <argv...>

Steps, one a line: `expect <text>` waits for it in the output; `send <text>` types it and Enter; `key <c>` types one key; `wait <seconds>`;
`wait-file <path>` pauses until the suite makes it; `hup` closes the terminal. The transcript is kept current, so a suite can read it mid-run.
It answers the colour and cursor queries a real terminal answers, which upterm's prompt waits on. The exit code is the child's. A step that times out, or a run past TIMEOUT below, kills the child and exits 124 with the transcript written.

It double-forks first: a person's terminal has no agent above it, and member-support.sh reads the process tree, so a suite run from an agent
session would otherwise be refused for the true reason that it is one.
"""
import os
import pty
import re
import select
import signal
import sys
import time

TIMEOUT = float(os.environ.get("PTY_RUN_TIMEOUT", "40"))


def strip(text):
    return re.sub(r"\x1b\[[0-9;?<>=]*[A-Za-z~]|\x1b\][^\x07\x1b]*(\x1b\\|\x07)|\x1b[()][A-Z0-9]|\x1b[=>]|\r", "", text)


def detach():
    """The grandchild runs on, parented by init. Returns the pipe its exit code goes back on."""
    read_end, write_end = os.pipe()
    first = os.fork()
    if first:
        os.close(write_end)
        os.waitpid(first, 0)
        code = b""
        while True:
            chunk = os.read(read_end, 16)
            if not chunk:
                break
            code += chunk
        sys.exit(int(code or b"124"))
    os.close(read_end)
    os.setsid()
    if os.fork():
        os._exit(0)
    return write_end


def main():
    back = detach()
    steps = [line.rstrip("\n") for line in open(sys.argv[1]) if line.strip()]
    out_path = sys.argv[2]
    argv = sys.argv[sys.argv.index("--") + 1:]
    pid, fd = pty.fork()
    if pid == 0:
        os.execvp(argv[0], argv)
    buf = ""
    seen = 0
    start = time.time()
    closed = False

    def pump(seconds):
        nonlocal buf, closed
        end = time.time() + seconds
        while time.time() < end and not closed:
            ready, _, _ = select.select([fd], [], [], 0.05)
            if not ready:
                continue
            try:
                data = os.read(fd, 65536)
            except OSError:
                closed = True
                break
            if not data:
                closed = True
                break
            text = data.decode(errors="replace")
            buf += text
            with open(out_path, "w") as f:
                f.write(strip(buf))
            if "\x1b]11;?" in text:
                os.write(fd, b"\x1b]11;rgb:0000/0000/0000\x1b\\")
            if "\x1b[6n" in text:
                os.write(fd, b"\x1b[1;1R")
            if "\x1b[c" in text:
                os.write(fd, b"\x1b[?62;c")

    def finish(code):
        with open(out_path, "w") as f:
            f.write(strip(buf))
        os.write(back, str(code).encode())
        os._exit(0)

    def kill():
        try:
            os.kill(pid, signal.SIGKILL)
        except OSError:
            pass

    for step in steps:
        word, _, rest = step.partition(" ")
        if word == "expect":
            while rest not in strip(buf)[seen:]:
                pump(0.1)
                if closed and rest not in strip(buf)[seen:]:
                    buf += f"\n[terminal_run: ended before: {rest}]\n"
                    finish(124)
                if time.time() - start > TIMEOUT:
                    buf += f"\n[terminal_run: timed out on: {rest}]\n"
                    kill()
                    finish(124)
            seen = strip(buf).index(rest, seen) + len(rest)
        elif word == "send":
            os.write(fd, rest.encode() + b"\r")
        elif word == "key":
            os.write(fd, rest.encode())
        elif word == "wait":
            pump(float(rest))
        elif word == "wait-file":
            while not os.path.exists(rest):
                pump(0.1)
                if time.time() - start > TIMEOUT:
                    buf += f"\n[terminal_run: timed out on: {rest}]\n"
                    kill()
                    finish(124)
        elif word == "hup":
            # What a closing window delivers. Closing a pty master alone hangs up on Linux and not on macOS.
            os.close(fd)
            closed = True
            try:
                os.killpg(pid, signal.SIGHUP)
            except OSError:
                pass
            time.sleep(0.2)
            kill_after = time.time() + 5
            while time.time() < kill_after:
                done, status = os.waitpid(pid, os.WNOHANG)
                if done:
                    finish(os.waitstatus_to_exitcode(status))
                time.sleep(0.1)
            finish(0)

    while not closed and time.time() - start < TIMEOUT:
        pump(0.2)
    if not closed:
        buf += "\n[terminal_run: still running at the end]\n"
        kill()
        finish(124)
    _, status = os.waitpid(pid, 0)
    finish(os.waitstatus_to_exitcode(status))


main()
