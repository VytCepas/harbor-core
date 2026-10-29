#!/usr/bin/env python3
"""access-chrome-mcp.py (harbor#1301, #555 P4) — `harbor chrome` as a local MCP server, `harbor_chrome`.
INTERPRETER EXCEPTION: python3, because an MCP server is a JSON-RPC loop over stdio, not a shell job; stdlib only.

  claude mcp add --scope user harbor_chrome -- python3 -I ~/.claude/bin/access-chrome-mcp.py

Why a server: a confined Bash command cannot reach the operator's logged-in Chrome (allowLocalBinding stays off), and
an MCP server runs outside the confinement, so sessions drive Chrome through these tools and never through localhost.
Each tool is one `harbor chrome` verb (mcp__harbor_chrome__<verb>, hyphens as underscores), so each has its own
permission entry; there is no server-wide allow. The tool runs bin/access-browser-agent.sh BESIDE THIS FILE with an argument
list, never a shell string, so every guardrail of the CLI (the verb allowlist, the host allowlist read from
contracts/browser-agent-hosts.txt then the private layer's browser-hosts.txt, the upload and filename checks) is the
one that decides. A project's settings `env` reaches this process too, so the CLI runs under /bin/sh with a fixed PATH
and only the locale, HOME, TMPDIR and session variables passed on: the CLI's own test seams (HARBOR_PW_CLI, the private
host list) cannot be set from a repo.
The CLI names its browser session from CLAUDE_CODE_SESSION_ID; without it this process names one per parent session
(mcp-<ppid>), so two sessions never share a page. `harbor chrome` on the CLI stays for the operator's own terminal."""
import json, os, subprocess, sys

HERE = os.path.dirname(os.path.realpath(__file__))
AGENT = os.path.join(HERE, 'access-browser-agent.sh')
PROTOCOLS = ('2025-06-18', '2025-03-26', '2024-11-05')
OUT_MAX = 100000
LONG = {'attach': 900, 'wait-signin': 900}   # both wait on the operator: a click in Chrome, a sign-in
VERBS = {
    'attach': 'connect to the operator\'s Chrome; the operator clicks Connect unless the extension token is registered',
    'status': 'this session\'s browser name, pin, profile and workdir',
    'state': 'the page\'s own visibility, focus and load state',
    'doctor': 'is harbor chrome ready on this box',
    'detach': 'release the operator\'s Chrome; always run it when done',
    'tabs': 'every Chrome tab by window, query strings cut; = marks this session\'s page',
    'front': 'make this session\'s tab the visible one, then give focus back',
    'wait-signin': 'wait (args: [seconds], default 300) while the operator signs in',
    'hosts': 'the host allowlist goto and tab_new read: core, then the private layer',
    'goto': 'open one https url (args: [url]) on an allowed host',
    'tab-new': 'open a tab (args: [] or [url] on an allowed host)',
    'tab-list': 'this session\'s tabs', 'tab-select': 'select a tab (args: [index])', 'tab-close': 'close a tab (args: [index])',
    'snapshot': 'the page as an accessibility tree with refs', 'find': 'find on the page (args: [text])',
    'screenshot': 'a screenshot (args: [] or [--filename=<bare name>]); it lands in the session workdir',
    'pdf': 'the page as a PDF (args: [--filename=<bare name>])',
    'go-back': 'history back', 'go-forward': 'history forward', 'reload': 'reload the page',
    'console': 'the page console', 'resize': 'resize the viewport (args: [width, height])',
    'click': 'click a ref (args: [ref] or [ref, button], --force, --modifiers=<key>)', 'dblclick': 'double-click a ref',
    'hover': 'hover a ref', 'fill': 'fill a field (args: [ref, text], --submit)', 'type': 'type text (args: [text], --submit)',
    'select': 'select an option (args: [ref, value])', 'check': 'check a ref', 'uncheck': 'uncheck a ref',
    'drag': 'drag (args: [from-ref, to-ref])', 'press': 'press a key (args: [key])',
    'keydown': 'key down (args: [key])', 'keyup': 'key up (args: [key])',
    'mousemove': 'move the mouse (args: [x, y])', 'mousedown': 'mouse down', 'mouseup': 'mouse up',
    'mousewheel': 'scroll (args: [dx, dy])', 'dialog-accept': 'accept the open dialog', 'dialog-dismiss': 'dismiss the open dialog',
    'upload': 'upload files (args: absolute paths) after a click opened the file chooser',
}
SCHEMA = {'type': 'object', 'additionalProperties': False, 'properties': {
    'args': {'type': 'array', 'items': {'type': 'string'}, 'description': 'the verb\'s arguments, as harbor chrome takes them'},
    'lane': {'type': 'string', 'description': 'a parallel agent\'s own browser session: 1-12 of a-z0-9'}}}

def tool_name(verb): return verb.replace('-', '_')
TOOLS = {tool_name(v): v for v in VERBS}

KEEP = ('HOME', 'USER', 'LOGNAME', 'LANG', 'LC_ALL', 'LC_CTYPE', 'TMPDIR', 'TERM', 'CLAUDE_CODE_SESSION_ID')
PATH = '/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin'

def session_env():
    env = {k: os.environ[k] for k in KEEP if os.environ.get(k)}
    env['PATH'] = PATH
    if not env.get('CLAUDE_CODE_SESSION_ID'):
        env['HARBOR_BROWSER_SESSION'] = 'mcp-%d' % os.getppid()
    return env

def call(name, arguments):
    verb = TOOLS.get(name)
    if verb is None: return 'unknown tool: %s' % name, True
    if not isinstance(arguments, dict): return 'arguments must be an object', True
    args = arguments.get('args', [])
    if not isinstance(args, list) or not all(isinstance(a, str) for a in args): return 'args must be a list of strings', True
    env = session_env()
    lane = arguments.get('lane')
    if lane is not None:
        if not isinstance(lane, str): return 'lane must be a string', True
        env['HARBOR_BROWSER_LANE'] = lane   # access-browser-agent.sh validates it
    try:
        r = subprocess.run(['/bin/sh', AGENT, verb] + args, env=env, stdin=subprocess.DEVNULL, capture_output=True,
                           text=True, timeout=LONG.get(verb, 180))
    except subprocess.TimeoutExpired:
        return 'harbor chrome %s did not finish within %d s' % (verb, LONG.get(verb, 180)), True
    except OSError as e:
        return 'harbor chrome could not start: %s' % e, True
    text = r.stdout
    if r.returncode != 0: text = (text + ('\n' if text else '') + r.stderr).strip() or 'exit %d' % r.returncode
    return text[:OUT_MAX], r.returncode != 0

def handle(msg):
    mid, method, params = msg.get('id'), msg.get('method'), msg.get('params') or {}
    if mid is None: return None   # a notification: initialized, cancelled
    if not isinstance(method, str): return {'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32600, 'message': 'invalid request'}}
    if not isinstance(params, dict): return {'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32602, 'message': 'params must be an object'}}
    if method == 'initialize':
        want = params.get('protocolVersion')
        result = {'protocolVersion': want if want in PROTOCOLS else PROTOCOLS[0], 'capabilities': {'tools': {}},
                  'serverInfo': {'name': 'harbor_chrome', 'version': '1'}}
    elif method == 'ping': result = {}
    elif method == 'tools/list':
        result = {'tools': [{'name': tool_name(v), 'description': 'harbor chrome %s: %s' % (v, d), 'inputSchema': SCHEMA}
                            for v, d in VERBS.items()]}
    elif method == 'tools/call':
        name = params.get('name')
        if not isinstance(name, str): return {'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32602, 'message': 'name must be a string'}}
        text, err = call(name, params.get('arguments') or {})
        result = {'content': [{'type': 'text', 'text': text}], 'isError': err}
    else:
        return {'jsonrpc': '2.0', 'id': mid, 'error': {'code': -32601, 'message': 'method not found: %s' % method}}
    return {'jsonrpc': '2.0', 'id': mid, 'result': result}

def main():
    for line in sys.stdin:
        line = line.strip()
        if not line: continue
        try: msg = json.loads(line)
        except ValueError:
            out = {'jsonrpc': '2.0', 'id': None, 'error': {'code': -32700, 'message': 'parse error'}}
        else:
            try:
                out = handle(msg) if isinstance(msg, dict) else {'jsonrpc': '2.0', 'id': None, 'error': {'code': -32600, 'message': 'invalid request'}}
            except Exception as e:   # one bad request must not end the session's browser tools
                out = {'jsonrpc': '2.0', 'id': msg.get('id') if isinstance(msg, dict) else None,
                       'error': {'code': -32603, 'message': 'internal error: %s' % type(e).__name__}}
        if out is not None:
            sys.stdout.write(json.dumps(out) + '\n'); sys.stdout.flush()

if __name__ == '__main__':
    main()
