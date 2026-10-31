#!/usr/bin/env sh
# standard-rename.sh (harbor#996 B2, B3) — the rename codemod: renames.tsv rows in; moved files, rewritten references, a residual list out.
#
#   sh bin/standard-rename.sh [--plan] <rows>        DRY RUN (the default): what moves, what is rewritten, what would be left
#   sh bin/standard-rename.sh --apply <rows>         git mv, rewrite every true reference, retire exemption rows, print the residual
#   sh bin/standard-rename.sh --residual <rows>      the residual list alone, for rows already applied
#   ... (--live | --dir PATH)                        add the box: hook commands, memory notes, LaunchAgents, old deployed copies
#   sh bin/standard-rename.sh --import <mapping.tsv> [--wave W] [--old PATH]...   add a mapping's rename rows to renames.tsv
#   sh bin/standard-rename.sh --pr-body [--report F] [--before R] [--after R] [--refs harbor#N]   the six-line PR body
#   <rows>: --id <id> and --wave <W>, each repeatable · --root <dir> (default this checkout)
#   --report <file> (default <root>/build/rename-report.tsv) · --before/--after: bin/test-suite-run.sh --results files
#   exit 0 residual 0 · 1 residual left, or a row or the box half refused · 2 usage · 3 unchecked
# platform: macOS-only — --live reads a ~/Library/LaunchAgents twin and its reload hint names `launchctl bootout/bootstrap`; Linux has no LaunchAgents, so no twin is found there (harbor#618).
#
# THE INPUT IS THE REGISTRY. Rows live in standards/naming/renames.tsv, and every new name must pass
# `lint-name.sh --check <surface>` with no finding, or the row is refused. aliases.tsv holds terms, not
# paths (research 12e §3), and the research/03 rename TSV is never read (12a §1).
#
# A TRUE REFERENCE, NOT A SUBSTRING. The token is the old basename when the file stays in its directory
# and its name has an extension (`admission-bash.sh`), else the whole old path (`bin/harbor`). It counts only
# when neither neighbour is [A-Za-z0-9_-], the rule harbor#961's mapping counted inbound_refs with. So
# `bin/harbor` inside `bin/housekeeping-clean.sh` is left alone, though the graph (bin/doc-graph-generate.sh) lists that
# line, because the graph keeps git grep -F's substring semantics; the report names every such site. A
# basename another tracked path also carries falls back to the whole path. A whole path is never the
# tail of another tracked path's name: right after that path's directory (`vendor/archify/` for
# `bin/x.mjs`) it names the other file, so it is no reference and no ambiguity; after a bare `/`, `./` or
# `$ROOT/` it still counts, which is how CODEOWNERS and shell code spell a root path. A whole path another
# tracked path carries any other way (as its start, or after a non-slash) is still ambiguous and refuses
# the row. A bare mention of such a path inside the other file's own directory (`docs/generated/plan.md` in skills/topology/EVALS, beside
# EVALS/docs/generated/plan.md), or on a line that also names the other file by its longer path, means that file: it is left as written,
# listed in the report as `relative` and warned, and is no residual. The graph indexes full paths only, so bare-name references
# (floor-install.sh's `admission-hook.sh admission-bash.sh`) are found by this scan; the report counts them.
#
# A CASE-ONLY MOVE goes in two steps. A case-insensitive disk finds `contracts/README.md` where
# `contracts/README.md` is, so "already exists" is judged by what the disk holds under that exact spelling
# and by whether it is the file moving; the move itself goes through a temporary name, and the disk's
# directory is renamed to the index's spelling once nothing tracked is left under the old one.
# A directory tracked in both spellings after a move is reported: it is one directory on such a disk.
#
# A SHIM IS A ROW WITH remove_by. A date asks for the old path to keep working until then: --apply writes, at the old path, a
# relative symlink to the new file, tracked and named in the report. A link serves whatever reaches the old path (an exec, a
# `source`, an interpreter, a read), which a forwarder that `exec`s would not. Every reference in the repo is still rewritten to
# the new name; the shim is for what the repo cannot reach (a deployed hook, a PATH link, another checkout). Its exemptions.tsv
# row stays while it lives. For a bin/*.sh, lint wants the old name in a contracts/cli.md table and in contracts/idle-tools.txt, so
# the shim carries one marked line in each (written and removed with it; a register the tree lacks is not invented).
# Past the date, --plan and --residual list it and --apply deletes it; a date already past when the row first runs writes none.
# A case-only move has no shim: it would be the file itself.
#
# THE ENV SURFACE (env:OLD to env:NEW) renames a name that is read, set and quoted, not a file. With a remove_by date it opens a
# window: a shell reader (`$OLD`, `${OLD}`, `${OLD:-d}`, also `-` `:?` `:=`) becomes `${NEW:-<the reader>}`, so both spellings
# work until the date, and that fallback is no residual; a setter (`OLD=v`, `export OLD`, a YAML or JSON key) and prose take the
# new name. What CLEARS the name clears both: `unset OLD` becomes `unset NEW OLD`, `OLD= cmd` becomes `NEW= OLD= cmd`. Anything
# else (awk ENVIRON, python, JS, `${OLD:+x}`, `${#OLD}`, `local OLD`, `\$OLD`, a quoted name) is left as written and is residual:
# a person decides it. The repo's own callers now set the new name, so a suite that sets the OLD one is what keeps the window
# proved, and the codemod writes none. Past the date --apply collapses `${NEW:-${OLD:-d}}` to `${NEW:-d}` and renames the rest;
# no remove_by is a plain rename. The old name's exemption row stays while the window is open.
#
# THE BOX IS A SECOND RUN, AFTER THE DEPLOY. Hook commands may name the new file only once it is
# installed, or the fail-closed wrapper denies every call. So: --apply rewrites the repo; deploy the
# renamed tree; then --apply with the target rewrites the hook commands, the memory notes and the
# LaunchAgent twins, and removes the old deployed copies and pins (backed up first). Until the new names
# are deployed, the box half refuses and says so. Outside the repo nothing is written without a target.
#
# THE RESIDUAL is every true reference to an old name left in a scanned scope, plus anything that names
# it in a way no rewrite reaches: a binary file, a symlink, an exemption row that is not the row being
# retired, a sibling repo (fleet, yard: read, never written here), a settings.json key other than a hook
# command, a deployed copy older than the rename. renames.tsv itself is the one place an old name stays.
# The work log (memory-store) is a dated record: counted, never rewritten.
#
# PYTHON CORE, like doc-graph-generate.sh, and for the same fit reason: overlapping byte-level regex with
# lookbehind over every tracked file, and JSON hook rewriting; POSIX tools have neither.
set -eu

case "$0" in */*) SRC="${0%/*}" ;; *) SRC=. ;; esac
SRC="$(CDPATH= cd -- "$SRC" && pwd -P)"
. "$SRC/library-log.sh"
LOG_FD=2; log_init standard-rename

usage() { sed -n '2,13p' "$SRC/standard-rename.sh" | sed 's/^# \{0,1\}//'; }
_usage_error() { log_fail "$1"; log_fix "sh bin/standard-rename.sh --help"; log_end || :; exit 2; }

MODE=plan; ROOT=""; REPORT=""; IDS=""; WAVES=""; OLDS=""; MAPPING=""; BEFORE=""; AFTER=""; REFS=""
BOXARGS=""; APPLY=0
_need() { [ "$#" -ge 2 ] && [ -n "$2" ] && case "$2" in -*) false ;; *) true ;; esac || _usage_error "$1 needs a value"; }
while [ "$#" -gt 0 ]; do
  case "$1" in
    --plan) MODE=plan ;;
    --apply) MODE=apply; APPLY=1 ;;
    --residual) MODE=residual ;;
    --import) _need "$@"; MODE=import; MAPPING="$2"; shift ;;
    --pr-body) MODE=pr-body ;;
    --id) _need "$@"; IDS="$IDS $2"; shift ;;
    --wave) _need "$@"; WAVES="$WAVES $2"; shift ;;
    --old) _need "$@"; OLDS="$OLDS
$2"; shift ;;
    --root) _need "$@"; ROOT="$2"; shift ;;
    --report) _need "$@"; REPORT="$2"; shift ;;
    --before) _need "$@"; BEFORE="$2"; shift ;;
    --after) _need "$@"; AFTER="$2"; shift ;;
    --refs) _need "$@"; REFS="$2"; shift ;;
    --live) BOXARGS="$BOXARGS --live" ;;
    --dir) _need "$@"; BOXARGS="$BOXARGS --dir $(printf '%s' "$2" | sed "s/'/'\\\\''/g; s/^/'/; s/\$/'/")"; shift ;;
    -h|--help) usage; exit 0 ;;
    *) _usage_error "unknown argument $1" ;;
  esac
  shift
done
[ -n "$ROOT" ] || ROOT="$SRC/.."
ROOT="$(CDPATH= cd -- "$ROOT" 2>/dev/null && pwd -P)" || _usage_error "--root is not a directory"
git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1 || _usage_error "--root $ROOT is not a git checkout"
[ -n "$REPORT" ] || REPORT="$ROOT/build/rename-report.tsv"
case "$MODE" in
  plan|apply|residual) [ -n "$IDS$WAVES" ] || _usage_error "name the rows: --id <id> or --wave <W> (never the whole register by default)" ;;
  import) [ -f "$MAPPING" ] || _usage_error "--import $MAPPING is not a file"
          [ -z "$BOXARGS" ] || _usage_error "--import writes renames.tsv only; it takes no target" ;;
  pr-body) [ -z "$BOXARGS" ] || _usage_error "--pr-body takes no target" ;;
esac
[ "$MODE" != residual ] || [ "$APPLY" = 0 ] || _usage_error "--residual is read-only"
if ! command -v python3 >/dev/null 2>&1; then
  log_fail "python3 is not on PATH: nothing was renamed or checked"
  log_fix "$(pkg_hint python3), then re-run"
  log_end || :; exit 3
fi

# The box target, through the install standard's own parser: physical paths, --dir onto live refused.
BOX=""; IL_BK=""
if [ -n "$BOXARGS" ]; then
  case "$MODE" in plan|apply|residual) ;; *) _usage_error "a target goes with --plan, --apply or --residual" ;; esac
  . "$SRC/deploy-install-lib.sh"
  eval "il_parse $BOXARGS $([ "$APPLY" = 1 ] && printf -- --apply)"
  il_target
  BOX="$IL_TARGET"
  [ -d "$BOX" ] || { log_fail "no config dir at $BOX"; log_fix "give the config dir the renamed tree was deployed to"; log_end || :; exit 1; }
  if [ "$APPLY" = 1 ] && [ "$IL_LIVE" = 1 ] && [ -n "${CLAUDECODE:-}" ]; then
    log_fail "refused: --apply --live runs only from a terminal, never inside a Claude session"
    log_fix "$(il_cmd)   # from a terminal window"
    log_end || :; exit 1
  fi
  [ "$APPLY" = 0 ] || [ -n "$IL_BK" ] || { log_fail "no backup dir under $BOX/backups: nothing on the box is touched"; log_nofix "the log-lib line above"; log_end || :; exit 1; }
fi

TMP="${TMPDIR:-/tmp}"; TMP="${TMP%/}/standard-rename.$$"
mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT INT TERM

_py() { # <subcommand> <key=value...> — the core; log lines go to $TMP/log as tag TAB message TAB fix
python3 - "$@" <<'PY'
import os, re, sys, json, glob, shutil, subprocess, datetime

WB = rb'A-Za-z0-9_\-'
COLS = ['id', 'old', 'new', 'surface', 'wave', 'remove_by', 'reason']
FILE_SURFACES = ('bin', 'path')
RX_ENV = re.compile(r'^[A-Z][A-Z0-9_]*$')
RX_ID = re.compile(r'^rename-[0-9]{4}$')
RX_DATE = re.compile(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$')
BOX_DIRS = ('bin', 'hooks', '.helm-pins', 'skills', 'commands', 'agents', 'context-rules', 'inject.d', 'output-styles')
REG = 'standards/naming/renames.tsv'
EXEMPT = 'standards/naming/exemptions.tsv'
RX_BLOCK = re.compile(rb'\b(BEGIN|END) (derived|generated)\b(?:[: ]+(?:by )?([A-Za-z0-9_.-]+(?:/[A-Za-z0-9_.-]+)+))?')

def enc(s): return s.encode('utf-8', 'surrogateescape')
def dec(b): return b.decode('utf-8', 'surrogateescape')

LOG = []
def log(tag, msg, fix=''):
    LOG.append((tag, msg.replace('\t', ' ').replace('\n', ' '), fix.replace('\t', ' ').replace('\n', ' ')))

def flush(a):
    with open(a['log'], 'w', encoding='utf-8', errors='surrogateescape') as f:
        for t, m, x in LOG:
            f.write('%s\t%s\t%s\n' % (t, m, x))

def git(root, *args, check=True):
    if args[0] in ('mv', 'rm', 'add'):
        MEMO.clear()    # a git move or removal changes what the disk holds under paths the memo may know
    r = subprocess.run(['git', '-C', root] + list(args), capture_output=True)
    if check and r.returncode:
        raise RuntimeError('git %s: %s' % (' '.join(args), dec(r.stderr).strip()))
    return r.stdout

def tracked(root):
    files = {}
    for rec in git(root, 'ls-files', '-s', '-z').split(b'\0'):
        if rec:
            meta, path = rec.split(b'\t', 1)
            files[dec(path)] = dec(meta.split(b' ')[0])
    return files

# ── case: a case-insensitive disk answers for a spelling it does not hold
def exact_exists(root, rel):
    """lexists, but under this exact spelling: `contracts/x` is not there when the disk holds `CONTRACTS/x`."""
    cur = root
    for part in rel.split('/'):
        try:
            if part not in os.listdir(cur):
                return False
        except OSError:
            return False
        cur = os.path.join(cur, part)
    return True

def taken(root, files, old, new):
    """Is `new` occupied by something other than `old` itself? Tracked, held under this spelling, or held as another
    file under a case variant. The moving file under a case variant of its own path is a case-only move: free."""
    if new in files:
        return True
    full = os.path.join(root, new)
    if not os.path.lexists(full):
        return False
    if exact_exists(root, new):
        return True
    try:
        return not os.path.samefile(os.path.join(root, old), full)
    except OSError:
        return True

def move(root, old, new):
    """git mv. True when it went through a temporary name: the disk already holds `new` under another spelling (a case-only
    change), which a git that does not fold case refuses and one that does leaves spelled as it was."""
    if not os.path.lexists(os.path.join(root, new)):
        git(root, 'mv', '--', old, new)
        return False
    tmp, n = old + '.rename-tmp', 0
    while os.path.lexists(os.path.join(root, tmp)):
        n += 1; tmp = '%s.rename-tmp%d' % (old, n)
    git(root, 'mv', '--', old, tmp)
    try:
        git(root, 'mv', '--', tmp, new)
    except RuntimeError:
        git(root, 'mv', '--', tmp, old, check=False)
        raise
    return True

def dirs_of(paths):
    out = set()
    for n in paths:
        parts = n.split('/')[:-1]
        out |= {'/'.join(parts[:i]) for i in range(1, len(parts) + 1)}
    return out

def settle_dirs(root, news, files):
    """A disk keeps the spelling a directory was created with: after `git mv CONTRACTS/a.md contracts/a.md` the index says
    contracts/ and the disk still says CONTRACTS/. Rename each such directory to the index's spelling through a temporary
    name, unless a tracked path still sits under the old spelling. Returns [(old, new)] renamed."""
    done = []
    for d in sorted(dirs_of(news), key=lambda x: (x.count('/'), x)):
        if exact_exists(root, d):
            continue
        par, comp = os.path.split(d)
        pabs = os.path.join(root, par) if par else root
        try:
            have = [x for x in os.listdir(pabs) if x.lower() == comp.lower()]
        except OSError:
            continue
        if len(have) != 1 or not os.path.isdir(os.path.join(pabs, have[0])):
            continue
        old_rel = (par + '/' if par else '') + have[0]
        if any(p.startswith(old_rel + '/') for p in files):
            continue
        src = os.path.join(pabs, have[0])
        MEMO.clear()
        os.rename(src, src + '.rename-tmp')
        os.rename(src + '.rename-tmp', os.path.join(pabs, comp))
        done.append((old_rel, d))
    return done

def case_collisions(paths, news):
    """[(new dir, other spelling, tracked paths under it)] for each directory the rows move INTO that `paths` (the tree after the
    move) also tracks under other letters, whether the rows left it behind or it was there already: one directory on a
    case-insensitive disk, two in the index. Two new directories spelled apart by the rows themselves are said once."""
    spells = {}
    for d in dirs_of(paths):
        spells.setdefault(d.lower(), set()).add(d)
    mine, out = dirs_of(news), []
    for d in sorted(mine):
        for o in sorted(spells.get(d.lower(), set()) - {d}):
            if o in mine and o < d:
                continue
            out.append((d, o, sum(1 for p in paths if p.startswith(o + '/'))))
    return out

# ── shims: with remove_by set, the old path is a relative symlink to the new one until that date
SHIM_MARK = 'forwarding shim (harbor#996 %s)'
IDLE_REG = 'contracts/idle-tools.txt'
CLI_REG = 'contracts/cli.md'
RX_BIN_TOOL = re.compile(r'^bin/[^/]+\.sh$')
CLI_HEAD = '| Script | Why it is not a verb |'

def today(): return datetime.date.today().isoformat()
def window(r): return r['remove_by'] != '-' and r['remove_by'] >= today()    # the shim, or the dual read, is due

def is_shim(root, files, r):
    """Is the tracked file at r's old path the symlink this row writes?"""
    p = r['old']
    if files.get(p) != '120000':
        return False
    try:
        t = os.readlink(os.path.join(root, p))
    except OSError:
        return False
    return os.path.normpath(os.path.join(os.path.dirname(p), t)) == r['new']

def write_shim(root, r):
    """The old path again, a relative symlink to the new one, staged. A link serves whatever reaches the old path: an exec, a
    `source`, an interpreter, a read. (A forwarder that `exec`s would replace a sourcing caller and hand an interpreter a
    shell script.) Returns the kind."""
    full = os.path.join(root, r['old'])
    os.makedirs(os.path.dirname(full), exist_ok=True)
    MEMO.clear()
    os.symlink(os.path.relpath(r['new'], os.path.dirname(r['old']) or '.'), full)
    git(root, 'add', '--', r['old'])
    return 'symlink'

# What lint asks of a bin/*.sh that is a shim. Its content, shebang and --help are the new file's (it is a link to it), but
# lint.cli-contract wants the NAME in a contracts/cli.md table and lint.tool-has-caller wants a caller or an idle line, and
# the codemod has just rewritten every caller. So a live shim carries one line in each, marked with its row id; both go
# with the shim. A register the tree lacks is not invented.
def lint_rows(r):
    b = os.path.basename(r['old'])
    why = '%s: a symlink to %s until %s, the old path of %s; nothing in the repo calls it' % (SHIM_MARK % r['id'], r['new'], r['remove_by'], r['id'])
    idle = None if b.endswith('-test.sh') else '%-22s IDLE  %s' % (b, why)
    return idle, '| `%s` | %s |' % (b, why.replace(r['new'], '`%s`' % r['new']))

def has_mark(root, rel, r):
    data = readb(os.path.join(root, rel))
    return data is not None and enc(SHIM_MARK % r['id']) in data

def lint_gaps(root, r):
    """[(register, why, fixable)] for the lines a live bin/*.sh shim still lacks: the register exists and has no line of this row."""
    out = []
    if not RX_BIN_TOOL.match(r['old']):
        return out
    idle, _cli = lint_rows(r)
    if idle and os.path.isfile(os.path.join(root, IDLE_REG)) and not has_mark(root, IDLE_REG, r):
        out.append((IDLE_REG, 'no line for the shim at %s (lint.tool-has-caller)' % r['old'], True))
    cli = readb(os.path.join(root, CLI_REG))
    if cli is not None and not has_mark(root, CLI_REG, r):
        out.append((CLI_REG, 'no table row for the shim at %s (lint.cli-contract)' % r['old'], enc(CLI_HEAD) in cli))
    return out

def write_lint_rows(root, r):
    """Add the shim's line to each register that lacks it: the idle list's end, the internal-scripts table's last row.
    Returns the registers written."""
    done = []
    idle, cli = lint_rows(r)
    for rel, line, table in ((IDLE_REG, idle, None), (CLI_REG, cli, CLI_HEAD)):
        if line is None or has_mark(root, rel, r):
            continue
        data = readb(os.path.join(root, rel))
        if data is None:
            continue
        ls = data.split(b'\n')
        if table is None:
            pos = len(ls) - 1 if ls[-1] == b'' else len(ls)
        else:
            head = next((i for i, x in enumerate(ls) if x.strip() == enc(table)), None)
            if head is None:
                continue
            pos = head + 2    # past the header and its separator row
            while pos < len(ls) and ls[pos].startswith(b'|'):
                pos += 1
        ls.insert(pos, enc(line))
        write_keep_mode(os.path.join(root, rel), b'\n'.join(ls))
        done.append(rel)
    return done

def strip_lint_rows(root, r):
    """Drop the shim's lines from the registers. Returns the registers changed."""
    done, mk = [], enc(SHIM_MARK % r['id'])
    for rel in (IDLE_REG, CLI_REG):
        data = readb(os.path.join(root, rel))
        if data is None or mk not in data:
            continue
        write_keep_mode(os.path.join(root, rel), b'\n'.join(x for x in data.split(b'\n') if mk not in x))
        done.append(rel)
    return done

# ── env: a name that is read, set and quoted rather than a file. During a window a reader reads the new name, then the old;
# a writer, a declaration and prose take the new name; anything else is left as written and listed.
PROSE_EXT = ('.md', '.html', '.txt', '.rst', '.tsv')
RX_OP = re.compile(rb':?[-=?]')
RX_DECL = re.compile(rb'(?:^|[\s;&|(])(?:export|readonly)\s+(?:-[A-Za-z]+\s+)*$')
RX_UNSET = re.compile(rb'(?:^|[\s;&|(])unset\s+(?:-v\s+)?$')
RX_SHADOW = re.compile(rb'(?:^|[\s;&|(])(?:local|declare|typeset)\s+(?:-[A-Za-z]+\s+)*$')
RX_KEY = re.compile(rb'\s*(?:-\s+)?"?$')

def brace_end(s, i):
    """The index just past the } that closes a ${ whose body starts at s[i:]; None when the line does not close it."""
    depth = 1
    while i < len(s):
        c = s[i:i + 1]
        if c == b'\\':
            i += 2
            continue
        if c == b'{':
            depth += 1
        elif c == b'}':
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    return None

def env_line(l, ER, erx, prose, cnt):
    """One line through the env rows. ER: old name -> (new name, 'window' | 'plain'). cnt counts the changes per old name.
    A reader in a window becomes ${NEW:-<the reader>}: `$O` -> `${N:-$O}`, `${O}` -> `${N:-${O}}`, `${O:-d}` -> `${N:-${O:-d}}`.
    What CLEARS the name must clear both while readers still fall back to the old one: `unset O` -> `unset N O`, `O= cmd` -> `N= O= cmd`."""
    out, pos = [], 0
    for m in erx.finditer(l):
        s, e = m.start(1), m.end(1)
        if s < pos:
            continue
        o = m.group(1); n, how = ER[o]; pre = l[:s]
        if how == 'plain' or prose:
            out += [l[pos:s], n]; pos = e; cnt[o] = cnt.get(o, 0) + 1
            continue
        if pre.endswith(b'${' + n + b':-${') or pre.endswith(b'${' + n + b':-$'):
            continue    # the fallback of a read already written
        if pre.count(b"'") % 2:
            continue    # inside single quotes it is a program for awk or sed, or a trap run later: a person decides it
        if pre.endswith((b'unset ' + n + b' ', b'unset -v ' + n + b' ', n + b'= ')):
            continue    # the second name of a clearing already written
        d = len(pre) - 2 if pre.endswith(b'${') else len(pre) - 1 if pre.endswith(b'$') else -1
        if d >= 0:
            k = 0
            while d - k > 0 and pre[d - k - 1:d - k] == b'\\':
                k += 1
            if k % 2:
                continue    # `\$O` is a mention or a line of a script this one writes: a person decides which
        if pre.endswith(b'${'):
            if l[e:e + 1] == b'}':
                out += [l[pos:s - 2], b'${' + n + b':-${' + o + b'}}']; pos = e + 1; cnt[o] = cnt.get(o, 0) + 1
                continue
            mo = RX_OP.match(l, e)
            end = brace_end(l, mo.end()) if mo else None
            if end is not None:
                out += [l[pos:s - 2], b'${' + n + b':-', l[s - 2:end], b'}']; pos = end; cnt[o] = cnt.get(o, 0) + 1
            continue    # ${O:+x}, ${#O}, ${O%x}: no dual read wraps them, so they stay and are listed
        if pre.endswith(b'$') and not pre.endswith(b'$$'):
            out += [l[pos:s - 1], b'${' + n + b':-$' + o + b'}']; pos = e; cnt[o] = cnt.get(o, 0) + 1
            continue
        nxt = l[e:e + 1]
        if RX_UNSET.search(pre):
            out += [l[pos:s], n + b' ' + o]; pos = e; cnt[o] = cnt.get(o, 0) + 1
            continue
        if RX_SHADOW.search(pre):
            continue    # `local O` hides the old name inside a function and the new one stays visible: a person decides
        if nxt == b'=' and (l[e + 1:e + 2] in (b'', b' ', b'\t', b';', b'&', b'|', b')') or l[e + 1:e + 3] in (b'""', b"''")):
            out += [l[pos:s], n + b'= ' + o]; pos = e; cnt[o] = cnt.get(o, 0) + 1
            continue
        if (nxt == b'=' and l[e:e + 2] != b'==') or RX_DECL.search(pre) or (nxt == b':' and RX_KEY.match(pre)) or (pre.endswith(b'"') and l[e:e + 2] == b'":'):
            out += [l[pos:s], n]; pos = e; cnt[o] = cnt.get(o, 0) + 1
    out.append(l[pos:])
    return b''.join(out)

def collapse_line(l, CO, cnt):
    """A closed window: `${N:-${O<rest>}}` -> `${N<rest>}` and `${N:-$O}` -> `${N}`. CO: old name -> new name."""
    for o, n in CO.items():
        head, i = b'${' + n + b':-${' + o, 0
        while True:
            i = l.find(head, i)
            if i < 0:
                break
            j = i + len(head)
            end = brace_end(l, i + len(b'${' + n + b':-') + 2)
            if re.match(rb'[A-Za-z0-9_-]', l[j:j + 1]) or end is None or l[end:end + 1] != b'}':
                i = j
                continue
            l = l[:i] + b'${' + n + l[j:end - 1] + b'}' + l[end + 1:]
            cnt[o] = cnt.get(o, 0) + 1
            i += 1
        h2 = b'${' + n + b':-$' + o + b'}'
        if h2 in l:
            cnt[o] = cnt.get(o, 0) + l.count(h2)
            l = l.replace(h2, b'${' + n + b'}')
        # the clearings of an open window: `unset N O` -> `unset N`, `N= O=` -> `N=`
        l, c1 = re.subn(rb'(unset\s+(?:-v\s+)?)' + n + rb'\s+' + o + rb'(?![' + WB + rb'])', rb'\g<1>' + n, l)
        l, c2 = re.subn(rb'(?<![' + WB + rb'])' + n + rb'=\s+' + o + rb'=', n + b'=', l)
        if c1 + c2:
            cnt[o] = cnt.get(o, 0) + c1 + c2
    return l

def make_tline(rxw, repw, ER, erx, CO, claimed=None, marks=()):
    """A line transform for the repo rewrite and the plan's prediction: file tokens plain, env names by their rules.
    Returns the new line; `cnt` collects the env changes per old name, `plain` the file-token substitutions.
    `claimed(token, path, line)` leaves a mention that names another file; `marks` are the lines the codemod wrote itself."""
    def tline(l, path, cnt, plain):
        if marks and any(mk in l for mk in marks):
            return l
        pr = path.lower().endswith(PROSE_EXT) or l.lstrip()[:1] == b'#' or l.lstrip()[:2] == b'//'
        if CO:
            l = collapse_line(l, CO, cnt)
        if rxw is not None:
            cur = l
            def sub(m):
                t = m.group(1)
                if claimed is not None and claimed(t, path, cur):
                    return t
                plain[0] += 1
                return repw[t]
            l = rxw.sub(sub, l)
        if erx is not None:
            l = env_line(l, ER, erx, pr, cnt)
        return l
    return tline

MEMO = {}    # path -> bytes: the scans re-read every tracked file once per row; any write below forgets what it touched
def readb(p):
    if p in MEMO:
        return MEMO[p]
    try:
        with open(p, 'rb') as f:
            MEMO[p] = f.read()
        return MEMO[p]
    except OSError:
        return None

def binary(b): return b'\0' in b[:8000]

def bound(toks, shield=None):
    """The token regex: a name counts only when neither neighbour is a name character. `shield[tok]` lists the
    directories a token must not follow: right after one, it is the tail of another tracked path's name."""
    toks = sorted(set(toks), key=lambda t: (-len(t), t))
    shield = shield or {}
    alt = [b''.join(b'(?<!' + re.escape(enc(d)) + b')' for d in sorted(shield.get(t, ()))) + re.escape(enc(t)) for t in toks]
    return re.compile(rb'(?<![' + WB + rb'])(' + b'|'.join(alt) + rb')(?![' + WB + rb'])')

def lines_hit(data, rx):
    """[(line_no, line)] for every line holding a true reference."""
    return [(n, l) for n, l in enumerate(data.split(b'\n'), 1) if rx.search(l)]

def short(b, n=140):
    s = dec(b).strip().replace('\t', ' ')
    return s if len(s) <= n else s[:n - 1] + '…'

# ── the register
def register(root):
    path = os.path.join(root, REG)
    rows, errs, seen = [], [], {}
    if not os.path.isfile(path):
        return rows, ['%s is absent' % REG]
    with open(path, encoding='utf-8', errors='surrogateescape') as f:
        for ln, line in enumerate(f, 1):
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            c = line.split('\t')
            if c[0] == 'id':
                if c != COLS:
                    errs.append('%s:%d header is not: %s' % (REG, ln, ' '.join(COLS)))
                continue
            if len(c) != len(COLS):
                errs.append('%s:%d has %d columns, not %d' % (REG, ln, len(c), len(COLS)))
                continue
            r = dict(zip(COLS, c)); r['ln'] = ln
            bad = []
            if not RX_ID.match(r['id']): bad.append('id is not rename-NNNN')
            if not r['old'] or not r['new'] or r['old'] == r['new']: bad.append('old and new must be two paths')
            if r['surface'] == 'env':
                if not all(v.startswith('env:') and RX_ENV.match(v[4:]) for v in (r['old'], r['new'])):
                    bad.append('an env row names env:UPPER_CASE_NAME twice')
            elif r['old'].startswith('/') or r['new'].startswith('/') or r['old'].endswith('/') or r['new'].endswith('/'):
                bad.append('old and new are repo-relative file paths')
            if r['remove_by'] != '-' and not RX_DATE.match(r['remove_by']): bad.append('remove_by is - or YYYY-MM-DD')
            if not r['wave'] or not r['reason'] or not r['surface']: bad.append('surface, wave and reason are required')
            for k, v in (('id', r['id']), ('old', r['old']), ('new', r['new'])):
                if (k, v) in seen: bad.append('%s %s is already row %s' % (k, v, seen[(k, v)]))
                seen[(k, v)] = r['id']
            for b in bad:
                errs.append('%s:%d %s' % (REG, ln, b))
            rows.append(r)
    olds = {r['old'] for r in rows}
    for r in rows:
        if r['new'] in olds:
            errs.append('%s:%d new %s is another row\'s old: a chain renames twice' % (REG, r['ln'], r['new']))
    return rows, errs

def tails(prefix):
    """Every directory-suffix of a path prefix: skills/topology/ -> skills/topology/, topology/."""
    parts = prefix.split('/')[:-1]
    return {'/'.join(parts[i:]) + '/' for i in range(len(parts))}

def token(old, new, files):
    """(token, replacement, kind, others, shield, claim): the bare name when it stays in its dir and is unambiguous, else
    the whole path. `others` are tracked paths that carry the token in a way no text can tell apart. `shield` maps the token
    to the directories of tracked paths that END in it (vendor/archify/ for bin/x.mjs): those are not references. `claim` is
    the set of directories (vendor/archify) whose own file of that path sits beside the files inside them: a bare mention in
    one of those files means that file, not this one."""
    do, bo = os.path.split(old)
    dn, bn = os.path.split(new)
    if do == dn and '.' in bo.lstrip('.'):
        rx = bound([bo])
        others = sorted(p for p in files if p not in (old, new) and rx.search(enc(p)))
        if not others:
            return bo, bn, 'name', [], {}, set()
    rx = bound([old])
    others, shield, claim = [], set(), set()
    for p in sorted(files):
        if p in (old, new):
            continue
        pb, ds = enc(p), set()
        for m in rx.finditer(pb):
            if m.start() and pb[m.start() - 1:m.start()] == b'/':
                ds |= tails(dec(pb[:m.start()]))
                claim.add(dec(pb[:m.start() - 1]))
            else:
                ds = None
                break
        if ds is None:
            others.append(p)
        else:
            shield |= ds
    return old, new, 'path', others, {old: shield} if shield else {}, claim

def lint_findings(a, surface, name):
    r = subprocess.run(['sh', os.path.join(a['src'], 'lint-name.sh'), '--root', a['root'], '--check', surface, name,
                        '--format', 'findings'], capture_output=True)
    if r.returncode not in (0, 1):
        return ['lint-name exited %d: the name was not judged' % r.returncode]
    return [l for l in dec(r.stdout).splitlines() if l[:2] in ('A\t', 'V\t')]

def graph(a):
    """(edges, inputs) from bin/doc-graph-generate.sh, built now over this root."""
    r = subprocess.run(['sh', os.path.join(a['src'], 'doc-graph-generate.sh'), '--root', a['root'], '--stdout'], capture_output=True)
    if r.returncode != 0:
        return None, {}
    edges, inputs = [], {}
    for line in dec(r.stdout).split('\n'):
        if line.startswith('# input\t'):
            _i, label, where, status = line.split('\t')
            inputs[label] = (where, status)
        elif line and not line.startswith('#') and not line.startswith('edge\t'):
            edges.append(line.split('\t'))
    return edges, inputs

def expand(where, home):
    return home + where[1:] if where.startswith('~/') else where

# ── the box
def manifest_rows(cfg):
    rows = {}
    data = readb(os.path.join(cfg, '.harbor-manifest'))
    if data is None:
        return rows
    for line in dec(data).split('\n'):
        f = line.split(' ')
        if line.startswith('#') or len(f) < 5:
            continue
        rows[' '.join(f[2:-2])] = f[0]
    return rows

def box_names(cfg):
    out = []
    for d in BOX_DIRS:
        top = os.path.join(cfg, d)
        if not os.path.isdir(top):
            continue
        for dp, dns, fns in os.walk(top):
            dns[:] = [x for x in dns if x not in ('.git', '__pycache__')]
            for fn in fns:
                out.append(os.path.relpath(os.path.join(dp, fn), cfg))
    return sorted(out)

def notes_files(cfg):
    roots, out = set(), []
    for m in sorted(glob.glob(os.path.join(cfg, 'projects', '*', 'memory'))):
        r = os.path.realpath(m)
        if r in roots or not os.path.isdir(r):
            continue
        roots.add(r)
        for dp, dns, fns in os.walk(r):
            dns[:] = [x for x in dns if x != '.git']
            for fn in sorted(fns):
                out.append(os.path.join(dp, fn))
    return sorted(set(out))

def launch_twins(cfg, files):
    if os.path.basename(cfg.rstrip('/')) != '.claude':
        return []    # only a HOME's own .claude has a HOME whose LaunchAgents are ours to read
    la = os.path.join(os.path.dirname(cfg.rstrip('/')), 'Library', 'LaunchAgents')
    twins = {p[len('launchd/'):] for p in files if p.startswith('launchd/') and p.count('/') == 1}
    return [os.path.join(la, b) for b in sorted(os.listdir(la)) if b in twins] if os.path.isdir(la) else []

def hook_commands(j):
    """Every (container, key) whose value is a hook or status-line command."""
    out = []
    for ev in (j.get('hooks') or {}).values() if isinstance(j.get('hooks'), dict) else []:
        for grp in ev if isinstance(ev, list) else []:
            for h in grp.get('hooks', []) if isinstance(grp, dict) else []:
                if isinstance(h, dict) and isinstance(h.get('command'), str):
                    out.append((h, 'command'))
    for k in ('statusLine', 'subagentStatusLine'):
        if isinstance(j.get(k), dict) and isinstance(j[k].get('command'), str):
            out.append((j[k], 'command'))
    return out

def dedupe_hooks(j):
    n = 0
    for ev in (j.get('hooks') or {}).values() if isinstance(j.get('hooks'), dict) else []:
        for grp in ev if isinstance(ev, list) else []:
            if isinstance(grp, dict) and isinstance(grp.get('hooks'), list):
                seen, keep = set(), []
                for h in grp['hooks']:
                    k = json.dumps(h, sort_keys=True)
                    if k in seen:
                        n += 1
                        continue
                    seen.add(k); keep.append(h)
                grp['hooks'] = keep
    return n

def backup(a, path, cfg):
    rel = os.path.relpath(path, cfg) if path.startswith(cfg + '/') else os.path.basename(path)
    dst = os.path.join(a['bk'], rel)
    if not os.path.exists(dst):
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(path, dst, follow_symlinks=False)

def write_keep_mode(path, data):
    MEMO.pop(path, None)
    tmp = path + '.rename.%d' % os.getpid()
    with open(tmp, 'wb') as f:
        f.write(data)
    shutil.copymode(path, tmp)
    os.replace(tmp, path)

def remove_locked(path):
    MEMO.pop(path, None)
    d = os.path.dirname(path)
    mode = os.stat(d).st_mode
    try:
        if not os.access(d, os.W_OK):
            os.chmod(d, mode | 0o200)
        os.remove(path)
    finally:
        os.chmod(d, mode & 0o7777)

# ── the scan: every hit is (scope, where, why, fixable)
def scan(a, ctx):
    rx, rep, root, files = ctx['rx'], ctx['rep'], a['root'], ctx['files']
    pend_old = {r['old'] for r in ctx['pending']}
    pend_ex, keep_ex, shims, tline = ctx['retire'], ctx['keep_ex'], ctx['shim_paths'], ctx['tline']
    line_hit, kept_line = ctx['line_hit'], ctx['kept_line']
    out, ctx['claimed_sites'], ctx['shared_plan'], ctx['kept'] = [], [], [], []
    for p in sorted(files):
        mode = files[p]
        if p == REG or p in shims:
            continue
        if p not in pend_old and rx.search(enc(p)):
            if kept_line(enc(p), p):
                ctx['kept'].append((p, 0, enc(p)))
            else:
                out.append(('repo', p, 'a tracked path carries an old name', False))
        if mode == '160000':
            continue
        full = os.path.join(root, p)
        if mode == '120000':
            try:
                t = enc(os.readlink(full))
            except OSError:
                continue
            if rx.search(t) and kept_line(t, p):
                ctx['kept'].append((p, 0, t))
            elif rx.search(t):
                out.append(('repo', p, 'a symlink target names it: ' + short(t), False))
            continue
        data = readb(full)
        if data is None:
            continue
        hits = [(n, l) for n, l in enumerate(data.split(b'\n'), 1) if line_hit(l, p, ctx['claimed_sites'], n)]
        if not hits:
            continue
        if p == EXEMPT:
            for n, l in hits:
                c = l.split(b'\t')
                if len(c) == 6 and dec(c[2]) in keep_ex:
                    continue    # a live shim or dual read still needs the old name's exemption
                ok = len(c) == 6 and dec(c[2]) in pend_ex and c[3] == b'legacy'
                out.append(('repo', '%s:%d' % (p, n), ('a legacy row retired: ' if ok else 'an exemption row names it: ') + short(l), ok))
        elif binary(data):
            out.append(('repo', p, 'a binary file holds it', False))
        else:
            for n, l in hits:
                if kept_line(l, p):
                    ctx['kept'].append((p, n, l))
                    continue
                after = tline(l, p, {}, [0])
                fix = not line_hit(after, p) or (after != l and kept_line(after, p))
                if fix:
                    ctx['shared_plan'] += [(p, n, t, l) for t in ctx['shared_toks'](l, p)]
                out.append(('repo', '%s:%d' % (p, n), short(l) if fix else 'no rewrite decides this form: ' + short(l), fix))
    for r in ctx['shim_rows']:
        for rel, why, fixable in lint_gaps(root, r):
            out.append(('repo', rel, why, fixable))
    for name, sroot in ctx['siblings']:
        try:
            sf = tracked(sroot)
        except RuntimeError:
            continue
        for p in sorted(sf):
            data = readb(os.path.join(sroot, p)) if sf[p] not in ('120000', '160000') else None
            if data is None:
                continue
            if binary(data):
                if rx.search(data):
                    out.append(('sibling:' + name, p, 'a binary file holds it', False))
                continue
            for n, l in lines_hit(data, rx):
                out.append(('sibling:' + name, '%s:%d' % (p, n), short(l) + ' (a sibling PR)', False))
    cfg = a.get('box')
    if cfg:
        ctx['box_ready'] = True
        man = {k: v for k, v in manifest_rows(cfg).items() if k not in ctx.get('dropped', ())}
        names = box_names(cfg)
        old_copies = sorted(set([r for r in man if rx.search(enc(r))] + [n for n in names if rx.search(enc(n))]))
        ctx['old_copies'] = []
        for rel in old_copies:
            new_rel = dec(rx.sub(lambda m: rep[m.group(1)], enc(rel)))
            there = os.path.lexists(os.path.join(cfg, rel))
            if rel in ctx['shim_new']:
                # the deployed old path is the shim, kept on purpose; it forwards to the new file, which must be deployed first
                if not os.path.lexists(os.path.join(cfg, ctx['shim_new'][rel])):
                    ctx['box_ready'] = False
                    out.append(('box', rel, 'deployed under the old name and %s is not deployed: deploy the renamed tree first' % ctx['shim_new'][rel], False))
                elif there and rel not in ctx.setdefault('box_noted', set()):
                    ctx['box_noted'].add(rel)
                    log('note', '%s is deployed and kept: it keeps working until %s, and the next run after that date removes it' % (rel, ctx['shim_until'][rel]))
                continue
            if os.path.lexists(os.path.join(cfg, new_rel)):
                ctx['old_copies'].append((rel, there, rel in man))
                out.append(('box', rel, 'an old deployed copy (%s is deployed): removed, backed up' % new_rel, True))
            else:
                ctx['box_ready'] = False
                out.append(('box', rel, 'deployed under the old name and %s is not deployed: deploy the renamed tree first' % new_rel, False))
        old_set = {r for r, _t, _m in ctx['old_copies']}
        for rel in sorted(man):
            if rel in old_set or rx.search(enc(rel)):
                continue
            data = readb(os.path.join(cfg, rel))
            if data is not None and not binary(data) and rx.search(data):
                out.append(('box', rel, 'a deployed copy older than the rename: redeploy', False))
        for s in ('settings.json', 'settings.local.json'):
            p = os.path.join(cfg, s)
            data = readb(p)
            if data is None or not rx.search(data):
                continue
            try:
                j = json.loads(dec(data))
            except ValueError:
                out.append(('box', s, 'unparsable JSON names it', False)); continue
            nh = sum(len(rx.findall(enc(h[k]))) for h, k in hook_commands(j))
            nt = len(rx.findall(data))
            if nh:
                out.append(('box', s, '%d hook command reference(s)' % nh, True))
            if nt > nh:
                out.append(('box', s, '%d reference(s) outside the hook commands (a permissions rule? edit it, then floor-deny.sh --repin)' % (nt - nh), False))
        for p in notes_files(cfg):
            data = readb(p)
            if data is None or binary(data):
                continue
            for n, l in lines_hit(data, rx):
                out.append(('notes', '%s:%d' % (tilde(p, a), n), short(l), True))
        for p in launch_twins(cfg, files):
            data = readb(p)
            if data is not None:
                for n, l in lines_hit(data, rx):
                    out.append(('box', '%s:%d' % (tilde(p, a), n), short(l) + ' (launchctl bootout/bootstrap to reload)', True))
    return out

def tilde(p, a):
    h = a['home'].rstrip('/')
    return '~' + p[len(h):] if h and p.startswith(h + '/') else p

def kept_records(a, ctx):
    if not ctx.get('records'):
        return 0
    try:
        rf = tracked(ctx['records'])
    except RuntimeError:
        return 0
    n = 0
    for p in rf:
        data = readb(os.path.join(ctx['records'], p))
        if data is not None and not binary(data):
            n += len(ctx['rx'].findall(data))
    return n

# ── plan / apply / residual
def run(a):
    root, mode = a['root'], a['mode']
    rows, errs = register(root)
    for e in errs:
        log('FAIL', 'renames.tsv: ' + e, 'edit the row, then re-run')
    if errs:
        return 1
    ids, waves = a['ids'].split(), a['waves'].split()
    known = {r['id'] for r in rows}
    for i in ids:
        if i not in known:
            log('FAIL', 'no row %s in %s' % (i, REG), 'grep -n %s %s' % (i, REG)); return 1
    sel = [r for r in rows if r['id'] in ids or r['wave'] in waves]
    if not sel:
        log('FAIL', 'no row in %s matches --wave %s' % (REG, ' '.join(waves)), 'awk -F"\\t" \'{print $5}\' ' + REG + ' | sort -u')
        return 1
    for r in sel:
        if r['surface'] not in FILE_SURFACES + ('env',):
            log('FAIL', '%s: surface %s is not one the codemod moves yet (bin, path, env): nothing was done' % (r['id'], r['surface']), 'none automatic: harbor#996 open item')
            return 3
        if r['surface'] != 'env' and r['remove_by'] != '-' and r['old'].lower() == r['new'].lower():
            log('FAIL', '%s: a shim at %s would be the file %s itself on a case-insensitive disk' % (r['id'], r['old'], r['new']), 'drop remove_by: a case-only move leaves nothing to forward')
            return 1
    files = tracked(root)
    frows, erows = [r for r in sel if r['surface'] != 'env'], [r for r in sel if r['surface'] == 'env']
    pending, applied, expired, shimmed = [], [], [], []
    for r in frows:
        o, n = r['old'] in files, taken(root, files, r['old'], r['new'])
        if o and r['new'] in files and r['remove_by'] != '-' and is_shim(root, files, r):
            applied.append(r)
            if window(r):
                shimmed.append(r)
            else:
                expired.append(r)    # the shim outlived its date
        elif o and not n:
            pending.append(r)
        elif not o and r['new'] in files:
            applied.append(r)
        elif o and n:
            log('FAIL', '%s: %s already exists, so %s cannot move there' % (r['id'], r['new'], r['old']), 'pick another name in ' + REG); return 1
        else:
            log('FAIL', '%s: neither %s nor %s is tracked' % (r['id'], r['old'], r['new']), 'git ls-files | grep the name; fix the row'); return 1
    # The env rows: a name read, set and quoted, no file. `window` reads the new name, then the old; `plain` renames;
    # a closed window (remove_by passed) also collapses the dual reads it left.
    ER, CO = {}, {}
    for r in erows:
        o, n = r['old'][4:], r['new'][4:]
        ER[enc(o)] = (enc(n), 'window' if window(r) else 'plain')
        if r['remove_by'] != '-' and not window(r):
            CO[enc(o)] = enc(n)
        r['tok'], r['rep'], r['kind'], r['shield'] = o, n, 'env', {}
    erx = bound([dec(o) for o in ER]) if ER else None
    envpend = []
    if erows:
        tl0, cnt0 = make_tline(None, {}, ER, erx, CO), {}
        for p in sorted(files):
            if p in (REG, EXEMPT) or files[p] in ('120000', '160000'):
                continue
            data = readb(os.path.join(root, p))
            if data is None or binary(data) or not erx.search(data):
                continue
            for l in data.split(b'\n'):
                if erx.search(l):
                    tl0(l, p, cnt0, [0])
        # APPLIED IS DERIVED, as for a file (old absent, new tracked): an env row whose new name a code file already
        # carries was applied (a register or prose may name a new name before it exists, so they do not count), and an
        # old-name mention left beside it is a deliberate input (a suite proving the window) or a stale one that
        # --residual lists. A re-run rewrites none of them. A closed window still collapses.
        newin = set()
        nrx = bound([r['rep'] for r in erows])
        for p in sorted(files):
            if p in (REG, EXEMPT) or files[p] in ('120000', '160000') or p.lower().endswith(PROSE_EXT):
                continue
            data = readb(os.path.join(root, p))
            if data is not None and not binary(data):
                newin |= {dec(m.group(1)) for m in nrx.finditer(data)}
        envpend = [r for r in erows if cnt0.get(enc(r['tok']), 0) > 0
                   and (r['rep'] not in newin or (r['remove_by'] != '-' and not window(r)))]
    if mode == 'residual' and (pending or envpend):
        first = (pending + envpend)[0]
        log('FAIL', 'not applied yet: ' + ' '.join(r['id'] for r in pending + envpend), 'sh bin/standard-rename.sh --apply --id ' + first['id']); return 1
    pairs, refused, shield = [], False, {}
    for r in frows:
        tok, rep, kind, others, sh, cl = token(r['old'], r['new'], files)
        r['tok'], r['rep'], r['kind'], r['shield'], r['claim'] = tok, rep, kind, sh, cl
        shield.update(sh)
        if others:
            log('FAIL', '%s: %s also names %s, so a reference cannot be told apart' % (r['id'], tok, ', '.join(others[:3])), 'rename those in the same rows, or by hand')
            refused = True
        pairs.append((tok, rep))
    toks = [t for t, _ in pairs]
    if len(set(toks)) != len(toks):
        log('FAIL', 'two selected rows share a token: ' + ' '.join(toks), 'apply them in separate runs'); return 1
    if mode != 'residual':
        for r in pending + envpend:
            fs = lint_findings(a, r['surface'], r['new'][4:] if r['surface'] == 'env' else r['new'])
            if fs:
                nm = r['new'][4:] if r['surface'] == 'env' else r['new']
                log('FAIL', '%s: the registry rejects %s: %s' % (r['id'], nm, '; '.join(f.split('\t')[1] for f in fs)),
                    'sh bin/lint-name.sh --check %s %s' % (r['surface'], nm))
                refused = True
    if refused:
        return 1
    # The same name inside a regex (`admission-bash[.]sh`, `admission-bash\.sh`) is still that name: rewritten too.
    spelled = []
    claimd = {r['tok']: r['claim'] for r in frows if r['claim']}
    owner = {r['tok']: r['id'] for r in frows}
    for t, x in pairs:
        spelled.append((t, x))
        if '.' in t:
            for esc in ('\\.', '[.]'):
                spelled.append((t.replace('.', esc), x.replace('.', esc)))
                owner[t.replace('.', esc)] = owner[t]
                if t in shield:
                    shield[t.replace('.', esc)] = shield[t]
                if t in claimd:
                    claimd[t.replace('.', esc)] = claimd[t]
    # Two regexes. `rxw` writes: the file tokens, plain. `rx` scans: those and the env names, with a window's own fallback
    # (`${NEW:-$OLD}`) shielded, since it is meant to stay.
    # A RE-RUN ON AN APPLIED ROW WRITES NOTHING IN THE REPO. The repo half ran when the row moved its file; what still names
    # the old path is a deliberate input (a test that feeds the old name) or a stale mention --residual lists. Rewriting it
    # again turned 21 files of deliberate W3 inputs into new names when the box half was run on main (harbor#961). So the
    # write takes only the tokens of rows this run applies; the scan and the box still read every selected row's.
    pend_ids = {r['id'] for r in pending}
    envact = {enc(r['tok']) for r in envpend}
    active = {enc(t) for t, _x in spelled if owner.get(t) in pend_ids} | envact
    wsp = [(t, x) for t, x in spelled if enc(t) in active]
    rxw = bound([t for t, _ in wsp], {t: v for t, v in shield.items() if enc(t) in active}) if wsp else None
    repw = {enc(t): enc(x) for t, x in wsp}
    ER_W = {o: v for o, v in ER.items() if o in envact}
    erx_w = bound([dec(o) for o in ER_W]) if ER_W else None
    CO_W = {o: n for o, n in CO.items() if o in envact}
    sh_all = dict(shield)
    for o, (n, how) in ER.items():
        if how == 'window':
            sh_all[dec(o)] = ['${%s:-${' % dec(n), '${%s:-$' % dec(n), 'unset %s ' % dec(n), 'unset -v %s ' % dec(n), '%s= ' % dec(n)]
    rx = bound([t for t, _ in spelled] + [dec(o) for o in ER], sh_all)
    rep = {enc(t): enc(x) for t, x in spelled}
    rep.update({o: n for o, (n, _how) in ER.items()})
    # A bare mention of a path inside a directory that holds a file of that path, or on a line that also names such a file by
    # its longer path, means that file: left as written and listed, since only a person can tell. The codemod's own register
    # lines for a live shim name the old path on purpose and are skipped.
    cdirs = {enc(t): tuple(d + '/' for d in sorted(ds)) for t, ds in claimd.items()}
    tailrx = {enc(t): re.compile(rb'(?:' + b'|'.join(re.escape(enc(d)) for d in sorted(shield[t], key=len, reverse=True)) + rb')'
                                 + re.escape(enc(t)) + rb'(?![' + WB + rb'])') for t in claimd if shield.get(t)}
    def claimed(t, p, l):
        ds = cdirs.get(t)
        if ds is None:
            return False
        if p.startswith(ds):
            return True
        tr = tailrx.get(t)
        return tr is not None and tr.search(l) is not None
    shim_rows = shimmed + [r for r in pending if window(r)]
    marks = [enc(SHIM_MARK % r['id']) for r in shim_rows + expired]
    def line_hit(l, p, sites=None, n=0):
        """Does the line hold a reference nobody has claimed? The claimed ones go to `sites`."""
        if not rx.search(l) or (marks and any(mk in l for mk in marks)):
            return False
        real = False
        for m in rx.finditer(l):
            if claimed(m.group(1), p, l):
                if sites is not None:
                    sites.append((p, n, m.group(1), l))
            else:
                real = True
        return real
    def shared_toks(l, p):
        """The tokens on a line that the rewrite takes and another tracked file also ends with."""
        return [m.group(1) for m in rx.finditer(l) if m.group(1) in cdirs and not claimed(m.group(1), p, l)]
    tline = make_tline(rxw, repw, ER_W, erx_w, CO_W, claimed, marks)
    def kept_line(l, p):
        """Does every unclaimed reference on the line belong to a row already applied? Then no run but --residual judges it."""
        if mode == 'residual':
            return False
        ts = [m.group(1) for m in rx.finditer(l) if not claimed(m.group(1), p, l)]
        return bool(ts) and not any(t in active for t in ts)
    # What keeps the old name's exemption row: a shim still due, a window still open. What retires it: the subject is gone.
    shims_now = {r['old'] for r in shimmed}
    keep_ex = shims_now | {r['old'] for r in pending if window(r)} | {r['old'] for r in erows if ER[enc(r['tok'])][1] == 'window'}
    retire = ({r['old'] for r in pending if not window(r)} | {r['old'] for r in expired}
              | {r['old'] for r in envpend if ER[enc(r['tok'])][1] != 'window'})
    edges, inputs = graph(a)
    ctx = dict(rx=rx, rep=rep, files=files, pending=pending, siblings=[], records=None, retire=retire, keep_ex=keep_ex, shim_paths=set(shims_now), tline=tline,
               line_hit=line_hit, kept_line=kept_line, kept=[], shared_toks=shared_toks, shared_done=[], shim_rows=shim_rows, shim_new={r['old']: r['new'] for r in shim_rows}, shim_until={r['old']: r['remove_by'] for r in shim_rows})
    for label in ('fleet', 'yard'):
        w, st = inputs.get(label, ('-', 'absent'))
        if st != 'absent':
            ctx['siblings'].append((label, expand(w, a['home'])))
    w, st = inputs.get('memory-store', ('-', 'absent'))
    if st != 'absent':
        ctx['records'] = expand(w, a['home'])
    rpt = []
    for r in sel:
        state = 'pending' if r in pending or r in envpend else 'applied'
        rpt.append(('row', r['id'], r['old'], r['new'], r['surface'], r['wave'], r['tok'], r['rep'], state))
    # The graph's view of each pending path, before it moves: every site is a reference or a substring.
    if edges is None:
        log('WARN', 'bin/doc-graph-generate.sh did not build, so the graph cross-check was skipped', 'sh bin/doc-graph-generate.sh --stdout, and read the error')
    else:
        for r in pending:
            node = 'harbor:' + r['old']
            full = bound([r['old']], r['shield'])
            tokrx = bound([r['tok']], r['shield'])
            sites = sorted({e[3] for e in edges if e[0] == 'references' and e[2] == node and e[1].startswith('harbor:') and e[1] != 'harbor:' + REG})
            nref = nsub = 0
            for s in sites:
                path, ln = s[len('harbor:'):].rsplit(':', 1)
                data = readb(os.path.join(root, path)) or b''
                lines = data.split(b'\n')
                line = lines[int(ln) - 1] if 0 < int(ln) <= len(lines) else b''
                if full.search(line) or tokrx.search(line):
                    nref += 1
                else:
                    nsub += 1
                    rpt.append(('substring', r['old'], s[len('harbor:'):], short(line)))
            bare = 0
            for p in files:
                if p == REG or files[p] in ('120000', '160000'):
                    continue
                data = readb(os.path.join(root, p))
                if data is None or binary(data):
                    continue
                for _n, l in lines_hit(data, tokrx):
                    if enc(r['old']) not in l:
                        bare += 1
            rpt.append(('graph', r['old'], str(len(sites)), str(nref), str(nsub), str(bare)))
            log('ok', '%s: the graph lists %d site(s) of %s: %d reference(s), %d inside a longer name (left alone); %d more line(s) name it bare, which the graph does not index'
                % (r['id'], len(sites), r['old'], nref, nsub, bare))
    before = scan(a, ctx)
    late = [('repo', r['old'], 'the shim outlived its remove_by %s' % r['remove_by'], mode == 'plan') for r in expired if mode != 'apply']
    if mode == 'plan':
        before += late    # --apply removes it
    fixable = [h for h in before if h[3]]
    if mode == 'plan':
        for r in pending:
            log('note', '%s: would move %s to %s (token %s, %s%s)%s' % (r['id'], r['old'], r['new'], r['tok'], r['kind'],
                ', two steps: the disk holds the other spelling' if os.path.lexists(os.path.join(root, r['new'])) else '',
                ' and leave a symlink shim at %s until %s' % (r['old'], r['remove_by']) if window(r) else
                (' (remove_by %s has passed: no shim)' % r['remove_by'] if r['remove_by'] != '-' else '')))
        for r in applied:
            log('note', '%s: already applied (%s is tracked)%s' % (r['id'], r['new'],
                ' with its shim at %s until %s' % (r['old'], r['remove_by']) if r['old'] in shims_now else ''))
        for r in envpend:
            how = ER[enc(r['tok'])][1]
            log('note', '%s: would rewrite env %s to %s (%s)' % (r['id'], r['tok'], r['rep'],
                'readers read the new name, then the old, until %s' % r['remove_by'] if how == 'window' else 'plain' + (', closing the window of %s' % r['remove_by'] if r['remove_by'] != '-' else '')))
        for r in expired:
            log('note', '%s: the shim at %s outlived %s: --apply removes it' % (r['id'], r['old'], r['remove_by']))
        by = {}
        for h in fixable:
            by[h[0]] = by.get(h[0], 0) + 1
        log('note', 'lines to rewrite: ' + (', '.join('%s %d' % kv for kv in sorted(by.items())) or 'nothing'))
        if a.get('box') and not ctx.get('box_ready', True):
            log('note', 'the box half would refuse until the renamed tree is deployed')
        res = [h for h in before if not h[3]]
    else:
        if mode == 'apply':
            for r in pending:
                d = os.path.dirname(os.path.join(root, r['new']))
                os.makedirs(d, exist_ok=True)
                two = move(root, r['old'], r['new'])
                rpt.append(('moved', r['old'], r['new']))
                log('ok', '%s: git mv %s %s%s' % (r['id'], r['old'], r['new'], ' (two steps: the disk held the other spelling)' if two else ''))
            for r in expired:
                git(root, 'rm', '-q', '--', r['old'])
                rpt.append(('shim-removed', r['id'], r['old'], r['remove_by']))
                log('ok', '%s: removed the shim at %s (remove_by %s has passed)' % (r['id'], r['old'], r['remove_by']))
                for rel in strip_lint_rows(root, r):
                    rpt.append(('shim-rows-removed', r['id'], rel))
                    log('ok', '%s: dropped the shim\'s line from %s' % (r['id'], rel))
            files = tracked(root)
            ctx['files'] = files
            for od, nd in settle_dirs(root, [r['new'] for r in pending], files):
                rpt.append(('respelled', od, nd))
                log('ok', 'the directory %s is now spelled %s on the disk' % (od, nd))
            olds = set(retire)
            nrw = nfiles = 0
            envdone = {}
            for p in sorted(files):
                if p in (REG, EXEMPT) or p in ctx['shim_paths'] or files[p] in ('120000', '160000'):
                    continue
                full = os.path.join(root, p)
                data = readb(full)
                if data is None or binary(data) or not rx.search(data):
                    continue
                plain, cnt = [0], {}
                was = data.split(b'\n')
                now = [tline(l, p, cnt, plain) for l in was]
                new = b'\n'.join(now)
                if new != data:
                    ctx['shared_done'] += [(p, k, t, a_) for k, (a_, b_) in enumerate(zip(was, now), 1) if a_ != b_ for t in shared_toks(a_, p)]
                ctx.setdefault('hit_lines', {})[p] = (data, {ln for ln, (a_, b_) in enumerate(zip(was, now), 1) if a_ != b_ or (line_hit(a_, p) and not kept_line(a_, p))})
                if new == data:
                    continue
                write_keep_mode(full, new)
                n = plain[0] + sum(cnt.values())
                for o, c in cnt.items():
                    envdone[o] = envdone.get(o, 0) + c
                rpt.append(('rewrite', 'repo', p, str(n)))
                nrw += n; nfiles += 1
            for r in envpend:
                how = ER[enc(r['tok'])][1]
                rpt.append(('env', r['id'], r['tok'], r['rep'], how, str(envdone.get(enc(r['tok']), 0))))
                log('ok', '%s: env %s -> %s, %d change(s) (%s)' % (r['id'], r['tok'], r['rep'], envdone.get(enc(r['tok']), 0),
                    'readers read both until %s' % r['remove_by'] if how == 'window' else 'plain'))
            for r in pending:
                if window(r):
                    kind = write_shim(root, r)
                    ctx['shim_paths'].add(r['old'])
                    rpt.append(('shim', r['id'], r['old'], kind, r['remove_by']))
                    log('ok', '%s: wrote a %s shim at %s until %s' % (r['id'], kind, r['old'], r['remove_by']))
            if any(window(r) for r in pending):
                files = tracked(root)
                ctx['files'] = files
            for r in shim_rows:
                if RX_BIN_TOOL.match(r['old']):
                    for rel in write_lint_rows(root, r):
                        rpt.append(('shim-rows', r['id'], rel))
                        log('ok', '%s: added the shim\'s line to %s (what lint.cli-contract and lint.tool-has-caller ask of a bin tool)' % (r['id'], rel))
            ex = os.path.join(root, EXEMPT)
            data = readb(ex)
            if data is not None and olds:
                keep, gone = [], 0
                for l in data.split(b'\n'):
                    c = l.split(b'\t')
                    if len(c) == 6 and dec(c[2]) in olds and c[3] == b'legacy':
                        rpt.append(('exemption', dec(c[0]), dec(c[1]), dec(c[2])))
                        gone += 1
                        continue
                    keep.append(l)
                if gone:
                    write_keep_mode(ex, b'\n'.join(keep))
                    log('ok', 'retired %d legacy row(s) in %s: their subject moved' % (gone, EXEMPT))
            if pending or envpend:
                log('ok', 'rewrote %d reference(s) in %d tracked file(s)' % (nrw, nfiles))
            cfg = a.get('box')
            if cfg and not ctx.get('box_ready', True):
                log('FAIL', 'the box half refused: a deployed copy has no counterpart under its new name, so a hook rewired now would name a missing file',
                    'deploy the renamed tree (sh %s/bin/deploy.sh --apply …, or the component installer with --dir), then re-run this command' % root)
            elif cfg:
                for s in ('settings.json', 'settings.local.json'):
                    p = os.path.join(cfg, s)
                    data = readb(p)
                    if data is None or not rx.search(data):
                        continue
                    try:
                        j = json.loads(dec(data))
                    except ValueError:
                        continue
                    n = 0
                    for h, k in hook_commands(j):
                        v, c = rx.subn(lambda m: rep[m.group(1)], enc(h[k]))
                        if c:
                            h[k] = dec(v); n += c
                    if n:
                        d = dedupe_hooks(j)
                        backup(a, p, cfg)
                        write_keep_mode(p, enc(json.dumps(j, indent=2, ensure_ascii=False) + '\n'))
                        rpt.append(('box', 'rewired', s, str(n)))
                        log('ok', '%s: %d hook command reference(s) rewired%s' % (s, n, ', %d duplicate hook(s) dropped' % d if d else ''))
                for p in notes_files(cfg) + launch_twins(cfg, files):
                    data = readb(p)
                    if data is None or binary(data) or not rx.search(data):
                        continue
                    new, n = rx.subn(lambda m: rep[m.group(1)], data)
                    backup(a, p, cfg)
                    write_keep_mode(p, new)
                    rpt.append(('rewrite', 'box', tilde(p, a), str(n)))
                    log('ok', '%s: %d reference(s) rewritten' % (tilde(p, a), n))
                ctx['dropped'] = set()
                with open(a['drop'], 'w', encoding='utf-8', errors='surrogateescape') as f:
                    for rel, there, in_man in ctx.get('old_copies', []):
                        if there:
                            backup(a, os.path.join(cfg, rel), cfg)
                            remove_locked(os.path.join(cfg, rel))
                        if in_man:
                            f.write(rel + '\n')
                            ctx['dropped'].add(rel)
                        rpt.append(('box', 'removed', rel, '1'))
                        log('ok', 'removed the old deployed copy %s (backed up)' % rel)
        res = scan(a, ctx) + (late if mode == 'residual' else [])
    # A NAME NO TEXT REACHES. Measured on the sandbox rename of bin/admission-bash.sh (residual 0, floor-verify
    # green): seven suites went red, every one on a site that names the file through its family rather
    # than its name: `bin/guard-$g.sh` built at run time, the glob `bin/guard-*.sh`, the guard's own
    # self-protection regex `(guard|floor)-[a-z-]*\.(sh|awk)`. No rewrite can decide those, and no residual
    # can prove them, so they are listed for a person, and the suite ledger is the backstop. The list is
    # the family word (`guard`) next to a glob or regex character, or a variable standing for it.
    for r in frows:
        b = r['old'].rsplit('/', 1)[-1]
        stem, dot, ext = b.partition('.')
        word = stem.split('-', 1)[0]
        if '-' not in stem or not word:
            continue
        w = re.escape(enc(word))
        var = rb'\$\{?[A-Za-z_][A-Za-z0-9_]*\}?'
        crx = re.compile(rb'(?<![' + WB + rb'])' + w + rb'(?:-(?:[*?\[$({%]|\.\*)|\|[A-Za-z]|\)-)'
                         rb'|[(|]' + w + rb'(?:\||\)-)'
                         rb'|' + var + re.escape(enc(stem[len(word):] + dot + ext)) + rb'(?![' + WB + rb'])')
        for p in sorted(ctx['files']):
            if p == REG or ctx['files'][p] in ('120000', '160000'):
                continue
            data = readb(os.path.join(root, p))
            if data is None or binary(data):
                continue
            for n, l in lines_hit(data, crx):
                rpt.append(('pattern', r['id'], '%s:%d' % (p, n), short(l)))
        hits = [t for t in rpt if t[0] == 'pattern' and t[1] == r['id']]
        if hits:
            log('WARN', '%s: %d line(s) in %d file(s) reach %s through its family `%s` (a glob, a regex, a built name; first %s): no rewrite decides them, so a person does, and the suite ledger checks'
                % (r['id'], len(hits), len({t[2].rsplit(':', 1)[0] for t in hits}), b, word, hits[0][2]), 'grep ^pattern %s' % a['report'])
    # A MENTION THAT NAMES ANOTHER FILE: the same path beside the file that says it (vendor/archify/bin/x.mjs in a file of
    # vendor/archify), or the longer path on the same line. Rewriting it would point the other file's own docs at this one, so it
    # stays as written and is listed: a person reads the line, and the residual does not wait on it.
    cl = {}
    for p, n, t, l in ctx.get('claimed_sites', []):
        cl.setdefault(owner.get(dec(t), '-'), {})[(p, n)] = l
    for rid in sorted(cl):
        sites = sorted(cl[rid].items())
        for (p, n), l in sites:
            rpt.append(('relative', rid, '%s:%d' % (p, n), short(l)))
        log('WARN', '%s: %d line(s) in %d file(s) name it where a file of the same path sits beside them or on the same line (first %s:%d): left as written, a person decides'
            % (rid, len(sites), len({p for (p, _n), _l in sites}), sites[0][0][0], sites[0][0][1]), 'grep ^relative %s' % a['report'])
    # A RENAMED PATH THAT ANOTHER FILE ALSO ENDS IN (PROVENANCE.md, vendor/skills/PROVENANCE.md): the rewrite takes a bare mention
    # for the root file, which prose in a neighbouring directory can contradict from the line above. No text decides it, so the
    # sites it took are listed for a person to read.
    sh = {}
    for p, n, t, l in (ctx['shared_plan'] if mode == 'plan' else ctx['shared_done'] if mode == 'apply' else []):
        sh.setdefault(owner.get(dec(t), '-'), {})[(p, n)] = l
    byid = {r['id']: r for r in frows}
    for rid in sorted(sh):
        sites = sorted(sh[rid].items())
        for (p, n), l in sites:
            rpt.append(('shared', rid, '%s:%d' % (p, n), short(l)))
        log('WARN', '%s: %d line(s) in %d file(s) name %s, which %d other tracked file(s) also end with (first %s:%d): the rewrite takes it for this one, each worth a look'
            % (rid, len(sites), len({p for (p, _n), _l in sites}), byid[rid]['tok'] if rid in byid else '?', len(byid[rid]['claim']) if rid in byid else 0,
               sites[0][0][0], sites[0][0][1]), 'grep ^shared %s' % a['report'])
    # TWO SPELLINGS OF ONE DIRECTORY: a case-only move that leaves a file behind (`CONTRACTS/x` beside `contracts/y`) is one
    # directory on a case-insensitive disk, and a checkout there collides. Listed, not residual: whether the straggler
    # moves or the rename stops is the table's call.
    post = set(ctx['files']) if mode != 'plan' else (set(files) - {r['old'] for r in pending}) | {r['new'] for r in pending}
    for nd, od, n in case_collisions(post, [r['new'] for r in frows]):
        rpt.append(('collision', nd, od, str(n)))
        log('WARN', '%d tracked path(s) still sit under %s, a second spelling of %s: one directory on a case-insensitive disk, so a checkout there collides' % (n, od, nd),
            'give those paths a row in the wave table, or leave %s as it is' % nd)
    # A generated file the rewrite touched is stale against its generator (lint T1, T1b): regenerate it.
    if edges is not None and mode == 'apply':
        gen = {}
        for e in edges:
            if e[0] == 'derives_from' and e[1].startswith('harbor:') and e[2].startswith('harbor:'):
                gen.setdefault(e[1][len('harbor:'):], set()).add(e[2][len('harbor:'):])
        for t in [t for t in rpt if t[0] == 'rewrite' and t[1] == 'repo' and t[2] in gen]:
            for g in sorted(gen[t[2]]):
                rpt.append(('regenerate', t[2], g))
                log('WARN', '%s is generated by %s and was rewritten as text' % (t[2], g), 'sh %s --apply' % g)
    # A generated BLOCK inside a kept file (`# BEGIN derived: bin/x.sh --write` … `# END derived`) is invisible to
    # the graph, which reads a file's first 10 lines: a rewrite inside one left it stale with no word (harbor#996,
    # the sandbox rename of bin/admission-destroy.sh: .agents/protected-paths.tsv, classify.test.sh red, residual 0).
    if mode == 'apply':
        said = {(t[1], t[2]) for t in rpt if t[0] == 'regenerate'}
        for p, (data, hit) in sorted(ctx.get('hit_lines', {}).items()):
            gen, lines = None, data.split(b'\n')
            for n, l in enumerate(lines, 1):
                m = RX_BLOCK.search(l)
                if m and m.group(1) == b'BEGIN':
                    gen = dec(m.group(3)).rstrip('.,;:') if m.group(3) else None
                    start = n
                elif m and gen is not None:
                    if gen in ctx['files'] and (p, gen) not in said and any(start < x < n for x in hit):
                        said.add((p, gen))
                        rpt.append(('regenerate', p, gen))
                        log('WARN', '%s holds a block generated by %s (line %d) and a rewrite landed inside it' % (p, gen, start),
                            'sh %s --write, or the generator\'s own write flag' % gen)
                    gen = None
    if ctx.get('kept'):
        ks = ctx['kept']
        for p, n, l in ks:
            rpt.append(('applied-kept', '%s:%d' % (p, n) if n else p, short(l)))
        log('note', '%d line(s) in %d file(s) name an old path of a row applied before this run (first %s): the repo half ran then, so this run leaves them; --residual judges them'
            % (len(ks), len({p for p, _n, _l in ks}), '%s:%d' % (ks[0][0], ks[0][1]) if ks[0][1] else ks[0][0]))
    kept = kept_records(a, ctx)
    if kept:
        rpt.append(('kept', 'records', str(kept)))
        log('note', 'the work log names an old path %d time(s): a dated record, kept as written' % kept)
    for r in frows:
        stem = r['tok'].rsplit('/', 1)[-1].split('.')[0]
        if stem and stem != r['tok'].rsplit('/', 1)[-1]:
            n = 0
            srx, trx = bound([stem]), bound([r['tok']])
            for p in ctx['files']:
                if p == REG or ctx['files'][p] in ('120000', '160000'):
                    continue
                data = readb(os.path.join(root, p))
                if data is not None and not binary(data):
                    n += len(srx.findall(data)) - len(trx.findall(data))
            if n > 0:
                rpt.append(('stem', r['id'], stem, str(n)))
                log('note', '%s: the stem `%s` still appears %d time(s) (a log or check id, or prose): another surface, not rewritten' % (r['id'], stem, n))
    if not a.get('box'):
        log('note', 'the box was not scanned: no --live or --dir, so hook commands, notes and deployed copies are unchecked')
    for h in res:
        rpt.append(('residual', h[0], h[1], h[2]))
    with open(a['report'], 'w', encoding='utf-8', errors='surrogateescape') as f:
        f.write('# rename report (harbor#996) - generated by bin/standard-rename.sh %s; read by --pr-body\n' % mode)
        for t in rpt:
            f.write('\t'.join(t) + '\n')
    sys.stdout.write('residual %d\n' % len(res))
    for h in res:
        sys.stdout.write('%s\t%s\t%s\n' % (h[0], h[1], h[2]))
    return 1 if res or LOG and any(t == 'FAIL' for t, _m, _x in LOG) else 0

# ── --import: a harbor#961 mapping table into renames.tsv
def do_import(a):
    root = a['root']
    rows, errs = register(root)
    for e in errs:
        log('FAIL', 'renames.tsv: ' + e, 'edit the row, then re-run')
    if errs:
        return 1
    files = tracked(root)
    with open(a['mapping'], encoding='utf-8', errors='surrogateescape') as f:
        lines = [l.rstrip('\n') for l in f if l.strip() and not l.startswith('#')]
    head = lines[0].split('\t') if lines else []
    need = ('old_path', 'new_path', 'wave', 'recommendation', 'reason')
    miss = [c for c in need if c not in head]
    if miss:
        log('FAIL', '%s has no column %s: not a harbor#961 mapping table' % (a['mapping'], ', '.join(miss)), 'pass bin.tsv, docs.tsv or another table with those columns')
        return 1
    col = {c: i for i, c in enumerate(head)}
    waves = set(a['waves'].split())
    only = {x for x in a['olds'].split('\n') if x}
    have = {r['old'] for r in rows}
    num = max([int(r['id'][7:]) for r in rows if RX_ID.match(r['id'])] + [0])
    skipped, out, mismatch = {}, [], 0
    def skip(why):
        skipped[why] = skipped.get(why, 0) + 1
    for l in lines[1:]:
        c = l.split('\t')
        g = lambda k: c[col[k]] if col[k] < len(c) else ''
        old, new, wave, rec = g('old_path'), g('new_path'), g('wave'), g('recommendation')
        if waves and wave not in waves: skip('another wave'); continue
        if only and old not in only: skip('not named by --old'); continue
        if rec != 'rename': skip('recommendation ' + (rec or '-')); continue
        if new.startswith('(') or old.endswith('/') or new.endswith('/'): skip('a directory or no target'); continue
        if re.search(r'\bshim\b', g('reason')): skip('asks for a shim'); continue
        if old in have: skip('already in renames.tsv'); continue
        if old not in files: skip('not tracked here'); continue
        tok, _rep, _kind, others, _shield, _claim = token(old, new, files)
        if 'ref_token' in col and g('ref_token') and g('ref_token') != tok:
            log('WARN', '%s: the mapping counted token %s, this tree gives %s (%s); skipped' % (old, g('ref_token'), tok, ', '.join(others[:2]) or 'a path token'),
                'add the row by hand once the token is settled')
            mismatch += 1; skip('token differs'); continue
        surface = g('surface') if 'surface' in col and g('surface') else ('bin' if old.startswith('bin/') else 'path')
        num += 1
        reason = re.sub(r'\s+', ' ', g('reason')).strip() or '-'
        out.append('\t'.join(('rename-%04d' % num, old, new, surface, wave or '-', '-', reason)))
        have.add(old)
    if out:
        p = os.path.join(root, REG)
        data = readb(p)
        if not data.endswith(b'\n'):
            data += b'\n'
        write_keep_mode(p, data + enc('\n'.join(out) + '\n'))
    log('ok', 'imported %d row(s) into %s' % (len(out), REG))
    for why, n in sorted(skipped.items()):
        log('note', 'skipped %d: %s' % (n, why))
    sys.stdout.write(''.join(r + '\n' for r in out))
    return 1 if mismatch and not out else 0

# ── --pr-body: six labelled lines from the report and the suite ledgers
def ledger(p):
    if not p:
        return None
    t = {}
    with open(p, encoding='utf-8', errors='surrogateescape') as f:
        for l in f:
            c = l.rstrip('\n').split('\t')
            if len(c) >= 5 and c[0] in ('pass', 'fail'):
                t[c[4]] = c[0]
    return t

def prbody(a):
    if not os.path.isfile(a['report']):
        log('FAIL', 'no report at %s' % a['report'], 'sh bin/standard-rename.sh --apply --id <id> first')
        return 1
    R = {}
    with open(a['report'], encoding='utf-8', errors='surrogateescape') as f:
        for l in f:
            if not l.startswith('#'):
                c = l.rstrip('\n').split('\t')
                R.setdefault(c[0], []).append(c[1:])
    rows, res = R.get('row', []), R.get('residual', [])
    if not rows:
        log('FAIL', '%s holds no rows' % a['report'], 'sh bin/standard-rename.sh --apply --id <id>'); return 1
    first = rows[0]
    more = ' and %d more' % (len(rows) - 1) if len(rows) > 1 else ''
    rw = [x for x in R.get('rewrite', []) if x[0] == 'repo']
    nref = sum(int(x[2]) for x in rw)
    dirs = {}
    for x in rw:
        d = x[1].split('/')[0] if '/' in x[1] else '(root)'
        dirs[d] = dirs.get(d, 0) + 1
    top = ', '.join('%s %d' % kv for kv in sorted(dirs.items(), key=lambda kv: (-kv[1], kv[0]))[:4])
    extra = ''
    if R.get('shim'):
        extra += '; %d shim(s) kept until %s' % (len(R['shim']), ', '.join(sorted({x[3] for x in R['shim']})))
    if R.get('shim-removed'):
        extra += '; %d expired shim(s) removed' % len(R['shim-removed'])
    if R.get('env'):
        extra += '; env: %d name(s), %d change(s), %d with a dual-read window' % (len(R['env']), sum(int(x[4]) for x in R['env']), sum(1 for x in R['env'] if x[3] == 'window'))
    nex = len(R.get('exemption', []))
    sub = len(R.get('substring', []))
    box = R.get('box', [])
    boxt = ('box: %d hook command(s) rewired, %d old deployed copies removed, %d note file(s) rewritten'
            % (sum(int(x[2]) for x in box if x[0] == 'rewired'), sum(1 for x in box if x[0] == 'removed'),
               sum(1 for x in R.get('rewrite', []) if x[0] == 'box'))) if box or any(x[0] == 'box' for x in R.get('rewrite', [])) \
        else 'box: not run here; after deploy, `sh bin/standard-rename.sh --apply --id %s --live`' % first[0]
    b, f = ledger(a['before']), ledger(a['after'])
    if b is not None and f is not None:
        newly = sorted(s for s, v in f.items() if v == 'fail' and b.get(s) != 'fail')
        cnt = lambda t: '%d/%d' % (sum(1 for v in t.values() if v == 'pass'), len(t))
        tested = 'suite ledger before %s pass, after %s pass (`bin/test-suite-run.sh --results`); residual %d.' % (cnt(b), cnt(f), len(res))
    else:
        newly = None
        tested = 'no suite ledger was given, so the suites are UNTESTED here; residual %d.' % len(res)
    if res:
        breaks = 'Not safe yet: residual %d, first `%s`.' % (len(res), res[0][1])
    elif newly:
        breaks = 'Suites newly failing: %s.' % ', '.join(newly[:4])
    elif newly is None:
        breaks = 'Residual 0, but no suite ledger, so breakage is unchecked.'
    else:
        breaks = 'Nothing: residual 0 and no suite went from pass to fail.'
    pat = R.get('pattern', [])
    if pat:
        breaks += ' %d line(s) reach the old name through a glob, regex or built name (first `%s`): each checked by hand?' % (len(pat), pat[0][1])
    rel = R.get('relative', [])
    if rel:
        breaks += ' %d line(s) name it where a file of the same path sits beside them (first `%s`): left as written, each checked by hand?' % (len(rel), rel[0][1])
    col = R.get('collision', [])
    if col:
        breaks += ' %d path(s) still sit under %s, a second spelling of %s.' % (sum(int(x[2]) for x in col), ', '.join('`%s`' % x[1] for x in col[:2]), col[0][0])
    regen = R.get('regenerate', [])
    if regen:
        breaks += ' Regenerate %s.' % ', '.join(sorted({'`%s`' % x[0] for x in regen}))
    merge = 'ready once CI is green.' if not res and newly == [] else 'blocked: %s.' % ('residual %d' % len(res) if res else 'suites' if newly else 'no suite ledger')
    out = [
        '**What:** `%s` becomes `%s`%s (standards/naming/renames.tsv %s). %d reference(s) rewritten in %d file(s), %d exemption row(s) retired; %d substring-only site(s) left alone.'
        % (first[1], first[2], more, ', '.join(r[0] for r in rows), nref, len(rw), nex, sub),
        '**Touches:** %s; %s%s.' % (top or 'no tracked file', boxt, extra),
        '**Breaks:** ' + breaks,
        '**Tested:** ' + tested,
        '**BPN:** not needed (harbor only).',
        '**Merge:** %s On a conflict, re-run the codemod on fresh main; never resolve by hand.' % merge,
    ]
    sys.stdout.write('\n'.join(out) + '\n')
    if a['refs']:
        sys.stdout.write('\nRefs: %s\n' % a['refs'])
    return 0

if __name__ == '__main__':
    cmd, kv = sys.argv[1], dict(x.split('=', 1) for x in sys.argv[2:])
    try:
        rc = {'run': run, 'import': do_import, 'pr-body': prbody}[cmd](kv)
    except RuntimeError as e:
        log('FAIL', str(e), 'read the git error above'); rc = 1
    except Exception:
        import traceback; traceback.print_exc()
        log('FAIL', 'the core raised: the run stopped where the traceback above says', 'none automatic — see bin/standard-rename.sh'); rc = 4
    flush(kv)
    sys.exit(rc)
PY
}

_relay() { # the core's log lines, through log-lib, so FAIL is always followed by its fix
  [ -f "$TMP/log" ] || return 0
  while IFS="$(printf '\t')" read -r _t _m _x; do
    case "$_t" in
      ok) log_ok "$_m" ;; note) log_note "$_m" ;;
      WARN) log_warn "$_m"; [ -z "$_x" ] || log_fix "$_x" ;;
      FAIL) log_fail "$_m"; log_fix "${_x:-none automatic — see bin/standard-rename.sh}" ;;
    esac
  done < "$TMP/log"
}

case "$MODE" in
  plan|apply|residual) log_head "$MODE$IDS$WAVES${BOX:+ · box $BOX}"; mkdir -p "${REPORT%/*}" ;;
  import) log_head "import $MAPPING" ;;
  pr-body) log_head "pr-body $REPORT" ;;
esac
_rc=0
case "$MODE" in
  plan|apply|residual)
    _py run "mode=$MODE" "root=$ROOT" "src=$SRC" "home=$HOME" "ids=$IDS" "waves=$WAVES" "report=$REPORT" \
      "box=$BOX" "bk=$IL_BK" "drop=$TMP/drop" "log=$TMP/log" || _rc=$? ;;
  import) _py import "root=$ROOT" "mapping=$MAPPING" "waves=$WAVES" "olds=$OLDS" "log=$TMP/log" || _rc=$? ;;
  pr-body) _py pr-body "report=$REPORT" "before=$BEFORE" "after=$AFTER" "refs=$REFS" "log=$TMP/log" || _rc=$? ;;
esac
_relay
# The install manifest's rows for the removed copies go through install-lib, the one writer of its format.
if [ -s "$TMP/drop" ] && [ "$APPLY" = 1 ]; then
  while IFS= read -r _rel; do il_manifest_drop "$_rel"; done < "$TMP/drop"
  il_manifest_write || _rc=1
fi
case "$_rc" in 0|1|3) ;; *) _rc=1 ;; esac
case "$MODE" in plan|apply|residual) [ ! -s "$REPORT" ] || log_note "the report is $REPORT; the residual list is on stdout" ;; esac
if log_end; then exit "$_rc"; else [ "$_rc" != 0 ] || _rc=1; exit "$_rc"; fi
