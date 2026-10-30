#!/usr/bin/env sh
# pack.sh (harbor#1149, D-80, D-84) - `harbor pack`: install a workload repo's harbor-pack/ box-wide, and remove it exactly.
#   sh pack.sh list (--live | --dir PATH)                          installed packs, and listed ones not installed
#   sh pack.sh install [<repo-id>...] (--live | --dir PATH)        DRY RUN (the default): the plan, nothing written
#   sh pack.sh install [<repo-id>...] --apply (--live | --dir PATH)
#   sh pack.sh remove <repo-id>... --apply (--live | --dir PATH)   delete what install wrote, nothing else
# No <repo-id> on install means every repo in harbor.toml `packs`. A refused pack is skipped by name, the rest
# still install, and the run exits 1. contracts/pack.md is the format, the refusals and the manifest.
# A pack's check rows are a checks.md fragment (plus an optional controls.tsv), the private layer's own shape; install puts
# them at checks.d/<repo-id>.md and recomposes the installed bin/docs/reference/checks.md through check-registry-generate.sh.
# A pack's commands on PATH are a shims.tsv (name TAB bin/<file>): install puts it at shims.d/<repo-id>.tsv, and deploy-shim-install.sh
# links ~/.local/bin/<name> to the installed copy, so core's own contracts/shims.tsv names no pack command.
set -eu

SRC="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
ROOT="${HARBOR_SCOPE_ROOT:-${HARBOR_ROOT:-$(CDPATH= cd -- "$SRC/.." && pwd)}}"
. "$SRC/library-log.sh"
. "$SRC/deploy-install-lib.sh"
log_init pack
LOG_FD=2
IL_LOG=0   # a pack run keeps no backups dir: install -> remove must leave the target byte-identical

VERB=''; IDS=''
il_opt() { # positional words only: the verb, then repo ids
  case "$1" in
    -*) IL_TAKE=0 ;;
    *) if [ -z "$VERB" ]; then VERB="$1"; else IDS="${IDS:+$IDS }$1"; fi; IL_TAKE=-1 ;;
  esac
}
il_parse "$@"
case "$VERB" in
  list|install|remove) ;;
  '') il_usage_error 'needs a verb: list, install or remove' ;;
  *) il_usage_error "unknown verb: $VERB" ;;
esac
il_target
T="$IL_TARGET"
MFD="$T/.harbor-packs"
[ -d "$T" ] || { log_fail "the target $T does not exist"; log_fix "mkdir -p '$T'"; log_end || :; exit 1; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pack.XXXXXX")" || exit 2
trap 'rm -rf "$WORK"' EXIT INT TERM
TAB="$(printf '\t')"

valid_id() { case "$1" in ''|*[!A-Za-z0-9._-]*|[!A-Za-z0-9]*) return 1 ;; esac; }
for _i in $IDS; do valid_id "$_i" || il_usage_error "'$_i' is not a repo id"; done

# Every refusal is one line naming the pack and the reason; the pack is skipped, nothing of it is written.
refuse() { log_fail "skipped $ID: $1"; log_fix "${2:-fix the pack in its repo, commit it, and run this again}"; return 1; }

# pack.toml: the flat subset (D-81), strings only. Prints key TAB value; exit 2 on any other shape.
read_toml() {
  tr -d '\r' < "$1" | awk '
    function bad(m) { printf "pack.toml:%d: %s\n", NR, m > "/dev/stderr"; exit 2 }
    BEGIN { k["name"] = k["version"] = k["harbor_version"] = k["description"] = 1 }
    { l = $0; sub(/^[ \t]+/, "", l) }
    l == "" || l ~ /^#/ { next }
    l !~ /^[a-z_]+[ \t]*=[ \t]*"[^"\\]*"[ \t]*(#.*)?$/ { bad("expected key = \"value\"") }
    { key = l; sub(/[ \t]*=.*/, "", key); if (!(key in k)) bad("unknown key " key); if (key in seen) bad("duplicate key " key)
      seen[key] = 1; v = l; sub(/^[^"]*"/, "", v); sub(/".*/, "", v); printf "%s\t%s\n", key, v }
    END { for (x in k) if (!(x in seen)) { printf "pack.toml: missing key %s\n", x > "/dev/stderr"; exit 2 } }'
}

# <constraint> <core>: exit 0 satisfied, 1 not, 2 malformed. Constraint: [op]N[.M], comma = AND.
ver_ok() {
  awk -v c="$1" -v core="$2" '
    function num(v,   a) { split(v, a, "."); return a[1] * 1000000 + (a[2] == "" ? 0 : a[2]) }
    BEGIN { n = split(c, p, /[ ]*,[ ]*/); k = num(core)
      for (i = 1; i <= n; i++) { s = p[i]; gsub(/^[ ]+|[ ]+$/, "", s)
        if (s !~ /^(>=|<=|>|<|=)?[0-9]+(\.[0-9]+)?$/) exit 2
        op = s; sub(/[0-9.]+$/, "", op); v = num(substr(s, length(op) + 1))
        if (op == ">=") ok = (k >= v); else if (op == "<=") ok = (k <= v); else if (op == ">") ok = (k > v)
        else if (op == "<") ok = (k < v); else ok = (k == v)
        if (!ok) exit 1 }
      exit 0 }'
}

core_version() { # the dispatcher's contract version, as N.0
  _v="$(sed -n 's/^CONTRACT_VERSION=\([0-9][0-9.]*\)$/\1/p' "$ROOT/bin/harbor" | head -n 1)"
  case "$_v" in *.*) printf '%s' "$_v" ;; *) printf '%s.0' "$_v" ;; esac
}

# A manifest row F/D <rel> per file or directory install made; header lines are `# key value`.
mf_rows() { awk -F'\t' -v t="$2" '$1 == t { print $2 }' "$MFD/$1.tsv" 2>/dev/null || :; }

plan_one() { # <id> - validate everything, write nothing; leaves $WORK/plan (src TAB rel) and $WORK/meta
  ID="$1"; : > "$WORK/plan"
  sh "$SRC/scope-roots.sh" --conf packs 2>/dev/null | awk -v i="$ID" '$0 == i { f = 1 } END { exit !f }' ||
    refuse "not listed in harbor.toml packs" "add \"$ID\" to packs in harbor.toml (contracts/private-layer.md)" || return 1
  # harbor-private is the private layer's own pack (harbor#1273): its checkout is what scope-roots.sh --private resolves, never a
  # repos.tsv row, so HARBOR_SCOPE_PRIVATE moves the layer and its pack together.
  if [ "$ID" = harbor-private ]; then
    DIR="$(sh "$SRC/scope-roots.sh" --private 2>/dev/null)" && [ -d "$DIR" ] || refuse "no private layer at ${DIR:-<unresolved>}" "sh bin/scope-roots.sh --private" || return 1
  else
    DIR="$(sh "$SRC/scope-roots.sh" --repo "$ID" 2>/dev/null)" && [ -n "$DIR" ] || refuse "no checkout registered for the repo" "add it to repos.tsv" || return 1
  fi
  PK="$DIR/harbor-pack"
  [ -f "$PK/pack.toml" ] || refuse "no harbor-pack/pack.toml in $DIR" || return 1
  COMMIT="$(git -C "$DIR" rev-parse --verify -q HEAD 2>/dev/null)" ||
    refuse "unpinned: $DIR is not a git checkout with a commit" "git init and commit, or clone the repo" || return 1
  [ -z "$(git -C "$DIR" status --porcelain --untracked-files=all -- harbor-pack 2>/dev/null)" ] ||
    refuse "dirty: harbor-pack/ has uncommitted or untracked changes" "commit or discard them in $DIR" || return 1
  read_toml "$PK/pack.toml" > "$WORK/meta" 2> "$WORK/meta.err" ||
    refuse "pack.toml: $(head -n 1 "$WORK/meta.err")" || return 1
  NAME="$(awk -F'\t' '$1 == "name" { print $2 }' "$WORK/meta")"
  VER="$(awk -F'\t' '$1 == "version" { print $2 }' "$WORK/meta")"
  HV="$(awk -F'\t' '$1 == "harbor_version" { print $2 }' "$WORK/meta")"
  case "$NAME" in ''|*[!abcdefghijklmnopqrstuvwxyz0-9-]*|-*) refuse "pack.toml name '$NAME' is not [a-z0-9-]" || return 1 ;; esac
  CORE="$(core_version)"
  _rc=0; ver_ok "$HV" "$CORE" || _rc=$?
  case "$_rc" in
    0) ;;
    1) refuse "needs harbor $HV, core is $CORE" "upgrade core, or use a pack release that fits $CORE" || return 1 ;;
    *) refuse "harbor_version '$HV' is not a constraint like \">=1.0\"" || return 1 ;;
  esac

  # Only what git tracks is installed, so an ignored file is never carried in.
  git -C "$DIR" ls-files -s -- harbor-pack | awk -F'\t' '{ split($1, a, " "); print a[1] "\t" $2 }' > "$WORK/files"
  while IFS="$TAB" read -r _m _p; do
    case "$_p" in *[!A-Za-z0-9._/-]*) refuse "path '$_p' has a character outside [A-Za-z0-9._/-]" || return 1 ;; esac
    _r="${_p#harbor-pack/}"
    [ "$_m" != 120000 ] || refuse "$_r is a symlink" || return 1
    _rl="$(printf '%s' "$_r" | tr 'A-Z' 'a-z')"   # APFS folds case: Guard-x resolves as guard-x (harbor#1149)
    case "/$_rl" in
      */hooks/*) refuse "carries a hooks/ directory ($_r): a pack may not install a hook" || return 1 ;;
      */guard-*|*/admission-*|*/library-admission*) refuse "carries a guard file ($_r): a pack may not install a guard (guard-*, admission-*, library-admission*)" || return 1 ;;
    esac
    case "$_r" in
      pack.toml|tests/*|README*) ;;
      checks.tsv) refuse "checks.tsv is retired: check rows are a checks.md fragment (contracts/pack.md)" "convert checks.tsv to checks.md, the register's own row shape, and commit it" || return 1 ;;
      checks.md) printf '%s\t%s\n' "$_p" "checks.d/$ID.md" >> "$WORK/plan" ;;
      controls.tsv) printf '%s\t%s\n' "$_p" "checks.d/$ID.controls.tsv" >> "$WORK/plan" ;;
      shims.tsv) printf '%s\t%s\n' "$_p" "shims.d/$ID.tsv" >> "$WORK/plan" ;;
      conf-keys.txt) printf '%s\t%s\n' "$_p" "conf-keys.d/$ID.txt" >> "$WORK/plan" ;;
      terms.tsv) printf '%s\t%s\n' "$_p" "terms.d/$ID.tsv" >> "$WORK/plan" ;;
      skills/*/*)
        _s="${_r#skills/}"; _s="${_s%%/*}"
        [ ! -e "$ROOT/skills/$_s" ] || refuse "skill $_s shadows a core skill" || return 1
        printf '%s\t%s\n' "$_p" "$_r" >> "$WORK/plan" ;;
      skill-packs/*/*/*) refuse "skill-packs/ is <skill>/<name>.md; $_r is nested" || return 1 ;;
      skill-packs/*/README.md) refuse "$_r: a pack file is skill-packs/<skill>/<name>.md and README.md is never read as a pack" || return 1 ;;
      skill-packs/*/*.md)
        # A pack that ADDS packs to a core skill, without claiming the skill's name or its directory (harbor#1149).
        _s="${_r#skill-packs/}"; _s="${_s%%/*}"; _sf="${_r##*/}"
        _core=0; for _c in "$ROOT"/skills/*/; do [ "${_c%/}" != "$ROOT/skills/$_s" ] || [ ! -d "$_c/packs" ] || _core=1; done
        [ "$_core" -eq 1 ] || refuse "$_r: core has no skill $_s with a packs/ directory to add to" "a pack may add packs only to a core skill that reads them (contracts/pack.md)" || return 1
        [ ! -e "$ROOT/skills/$_s/packs/$_sf" ] ||
          refuse "$_r is also in core skills/$_s/packs/: a pack in two places is a duplicate, and the reader refuses it" "remove it from one of them" || return 1
        printf '%s\t%s\n' "$_p" "$_r" >> "$WORK/plan" ;;
      skill-packs/*) refuse "$_r: skill-packs/ holds <skill>/<name>.md and nothing else" || return 1 ;;
      bin/*/*) refuse "bin/ is flat; $_r is nested" || return 1 ;;
      bin/*)
        _b="${_r#bin/}"; _bs="${_b%.sh}"; _b="$(printf '%s' "$_b" | tr 'A-Z' 'a-z')"; _bs="$(printf '%s' "$_bs" | tr 'A-Z' 'a-z')"
        for _c in "$ROOT"/bin/* $(sh "$ROOT/bin/deploy-hooks.sh" --engines --root "$ROOT" 2>/dev/null); do
          _cb="$(printf '%s' "${_c##*/}" | tr 'A-Z' 'a-z')"
          [ "$_cb" != "$_b" ] && [ "${_cb%.sh}" != "$_bs" ] || refuse "bin/$_b shadows the core command ${_cb}" || return 1
        done
        awk -F'\t' 'NF >= 4 && /^[a-z-]+\t/ { print $1 }' "$ROOT/bin/harbor" | awk -v b="$_bs" '$0 == b { f = 1 } END { exit f }' ||
          refuse "bin/$_b shadows the core verb harbor $_bs" || return 1
        printf '%s\t%s\n' "$_p" "$_r" >> "$WORK/plan" ;;
      # A pack's rules: context-rules/user/<f>.md, or the old inject.d/<f>.md for one release (harbor#1010); both land in
      # the installed box tier, context-rules/user/pack-<name>--<f>.md.
      context-rules/user/*/*|inject.d/*/*) refuse "${_r%/*}/ is flat; $_r is nested" || return 1 ;;
      context-rules/user/*.md|inject.d/*.md)
        # run: names a script beside the pack whose stdout may be a deny verdict (contracts/injection-rule.md).
        git -C "$DIR" show "HEAD:$_p" | tr -d '\r' | awk '/^[ \t]*run[ \t]*:/ { f = 1 } END { exit f }' ||
          refuse "inject pack $_r has run: (it could deny); packs inject notes only" || return 1
        printf '%s\t%s\n' "$_p" "context-rules/user/pack-$NAME--${_r##*/}" >> "$WORK/plan" ;;
      context-rules/user/*|inject.d/*) refuse "$_r is not a .md pack" || return 1 ;;
      context-rules/*) refuse "$_r: a pack's rules are context-rules/user/<f>.md; a repo scope is that repo's own" || return 1 ;;
      *) log_warn "$ID: $_r is not a pack entry and is not installed" ;;
    esac
  done < "$WORK/files"
  [ -s "$WORK/plan" ] || refuse "the pack installs nothing" || return 1

  # Stage the install set from HEAD, then gate and install only that copy: what is scanned is what lands (harbor#1149).
  rm -rf "$WORK/stage"; mkdir -p "$WORK/stage"
  while IFS="$TAB" read -r _s _r; do
    mkdir -p "$WORK/stage/${_r%/*}"
    git -C "$DIR" show "HEAD:$_s" > "$WORK/stage/$_r"
    if [ "$(git -C "$DIR" ls-files -s -- "$_s" | awk '{ print $1 }')" = 100755 ]; then chmod 755 "$WORK/stage/$_r"; else chmod 644 "$WORK/stage/$_r"; fi
    # Front matter is an ALLOWLIST, not a denylist (harbor#1149): canonical opener, top-level keys in contracts/pack-frontmatter-keys.txt (skill-pack-frontmatter-keys.txt for skill-packs/), never hooks.
    case "$_r" in checks.d/*) ;; *.[Mm][Dd])
      [ "$(head -c 3 "$WORK/stage/$_r" | od -An -tx1 | tr -d ' \n')" != efbbbf ] ||
        refuse "$_r starts with a UTF-8 BOM: front matter must be canonical" || return 1
      _fk=pack-frontmatter-keys.txt; case "$_r" in skill-packs/*|skills/*/packs/*) _fk=skill-pack-frontmatter-keys.txt ;; esac
      _fm="$(tr -d '\r' < "$WORK/stage/$_r" | awk -v al="$ROOT/contracts/$_fk" -v fkn="$_fk" '
        BEGIN { while ((getline l < al) > 0) if (l !~ /^#/ && l != "") ok[l] = 1 }
        NR == 1 { if (substr($0, 1, 3) != "---") exit 0
                  if ($0 != "---") { print "its opening line is not exactly ---"; bad = 1; exit 0 }
                  fm = 1; next }
        fm && $0 == "---" { fm = 2; exit 0 }
        fm && ($0 ~ /^[ \t]/ || $0 ~ /^[ \t]*$/ || $0 ~ /^#/) { next }
        fm { if ($0 !~ /^[a-z][a-z0-9_-]*:( .*)?$/) { print "a top-level line is not key: value"; bad = 1; exit 0 }
             k = $0; sub(/:.*/, "", k)
             if (k == "hooks") { print "it has a hooks: key (a pack may not register a hook)"; bad = 1; exit 0 }
             if (!(k in ok)) { print "key " k " is not in contracts/" fkn; bad = 1; exit 0 } }
        END { if (fm == 1 && !bad) print "front matter has no closing ---" }')"
      [ -z "$_fm" ] || refuse "$_r has non-canonical front matter: $_fm" || return 1 ;;
    esac
  done < "$WORK/plan"

  # Client-free (D-85): the export-mode leak gate over exactly the staged files (no tests/fixtures skip, no layers.tsv, binary as text).
  git -C "$WORK/stage" init -q . 2>/dev/null; git -C "$WORK/stage" add -f -A 2>/dev/null
  _lrc=0
  LEAKS_EXPORT=1 HARBOR_SCOPE_ROOT="$WORK/stage" LEAKS_CORE_PATTERNS="$ROOT/contracts/leak-patterns.tsv" sh "$SRC/lint-leaks.sh" --list > "$WORK/leaks.pack" 2> "$WORK/leaks.err" || _lrc=$?
  [ "$_lrc" -eq 0 ] || refuse "the leak gate could not run cleanly (exit $_lrc)" "sh bin/lint-leaks.sh --list, in $DIR" || return 1
  if [ -s "$WORK/leaks.pack" ]; then
    refuse "names a client or account ($(wc -l < "$WORK/leaks.pack" | tr -d ' ') leak hit(s), first $(head -n 1 "$WORK/leaks.pack")); a pack is client-free" \
      "move it to the private layer; the hit paths are as installed, relative to the target"
    return 1
  fi
  # Secrets (harbor#1274): gitleaks over the same stage, as deploy-push runs it; missing refuses. gitleaks's default rules
  # only: it reads a .gitleaks.toml from the scanned dir, and a pack must not allow-list its own secret.
  command -v gitleaks >/dev/null 2>&1 || { refuse "gitleaks is missing, so the pack was not scanned for secrets" "$(pkg_hint gitleaks)"; return 1; }
  printf '[extend]\nuseDefault = true\n' > "$WORK/gitleaks.toml"
  if ! ( cd "$WORK/stage" || exit 2; unset GITLEAKS_CONFIG GITLEAKS_CONFIG_TOML
         set -- --no-banner --redact --exit-code 1 --report-format json --report-path "$WORK/gitleaks.json" --config "$WORK/gitleaks.toml"
         if gitleaks dir --help >/dev/null 2>&1; then exec gitleaks dir "$@" .; else exec gitleaks detect --no-git "$@" --source .; fi
       ) > "$WORK/gitleaks.out" 2>&1; then
    _gh="$(sed -n 's/^ *"Fingerprint": "\(.*\)",\{0,1\}$/\1/p' "$WORK/gitleaks.json" 2>/dev/null | head -n 1)"
    if [ -n "$_gh" ]; then refuse "carries a secret (gitleaks: $_gh)" "take it out of the pack's tracked file; the hit is file:rule:line"
    else refuse "gitleaks could not scan the pack: $(tr -d '\033' < "$WORK/gitleaks.out" | sed 's/\[[0-9;]*m//g' | tail -n 1)" "gitleaks dir --redact . in the pack shows its error"; fi
    return 1
  fi

  # Shims (harbor#1149): every row links a command to a bin/ file THIS pack installs, under a name core's own table does not
  # own, once. deploy-shim-install.sh reads the installed copy, so a row it cannot resolve would be a link to nothing.
  if [ -f "$WORK/stage/shims.d/$ID.tsv" ]; then
    awk -F'\t' '{ print $2 }' "$WORK/plan" > "$WORK/plan.rels"
    _sm="$(tr -d '\r' < "$WORK/stage/shims.d/$ID.tsv" | awk -F'\t' -v rels="$WORK/plan.rels" -v core="$ROOT/contracts/shims.tsv" '
      BEGIN { while ((getline l < rels) > 0) have[l] = 1
              while ((getline l < core) > 0) { sub(/#.*/, "", l); split(l, c, "\t"); if (c[1] != "" && c[1] != "name") owned[c[1]] = 1 } }
      /^[ \t]*#/ || /^[ \t]*$/ { next }
      !hdr++ { if ($0 != "name\trel") { print "its header is not name, rel"; exit }; next }
      NF != 2 { print "line " NR " has " NF " columns, not 2"; exit }
      $1 !~ /^[A-Za-z0-9][A-Za-z0-9._-]*$/ { print "line " NR ": " $1 " is not a command name ([A-Za-z0-9._-])"; exit }
      $2 !~ /^bin\/[A-Za-z0-9._-]+$/ || !($2 in have) { print "line " NR ": " $2 " is not a bin/ file this pack installs"; exit }
      ($1 in owned) { print "line " NR ": " $1 " is a command core\047s contracts/shims.tsv owns"; exit }
      ($1 in seen) { print "line " NR ": " $1 " is listed twice"; exit }
      { seen[$1] = 1 }
      END { if (!hdr) print "it has no header row" }')"
    [ -z "$_sm" ] || refuse "shims.tsv: $_sm" "the shape is contracts/pack.md: name TAB bin/<file>, with the header row" || return 1
  fi

  # harbor.toml keys (#949): a pack declares the keys its own tools read, so core names none of them. One key per line,
  # [a-z][a-z0-9_]*, never a core key (scope-roots.sh --conf-keys) and never one another installed pack declares.
  if [ -f "$WORK/stage/conf-keys.d/$ID.txt" ]; then
    sh "$SRC/scope-roots.sh" --conf-keys > "$WORK/keys.core" 2>/dev/null || refuse "scope-roots.sh --conf-keys could not list core's keys" "sh bin/scope-roots.sh --conf-keys" || return 1
    : > "$WORK/keys.other"
    for _f in "$T"/conf-keys.d/*.txt; do
      [ -f "$_f" ] && [ "$_f" != "$T/conf-keys.d/$ID.txt" ] || continue
      tr -d '\r' < "$_f" | sed "s|\$|	${_f##*/}|" >> "$WORK/keys.other"
    done
    _km="$(tr -d '\r' < "$WORK/stage/conf-keys.d/$ID.txt" | awk -F'\t' -v core="$WORK/keys.core" -v other="$WORK/keys.other" '
      BEGIN { while ((getline l < core) > 0) c[l] = 1; while ((getline l < other) > 0) { split(l, o, "\t"); p[o[1]] = o[2] } }
      /^[ \t]*#/ || /^[ \t]*$/ { next }
      $0 !~ /^[a-z][a-z0-9_]*$/ { print "line " NR ": " $0 " is not a key ([a-z][a-z0-9_]*)"; exit }
      ($0 in c) { print "line " NR ": " $0 " is a core harbor.toml key"; exit }
      ($0 in p) { print "line " NR ": " $0 " is declared by the installed pack " p[$0]; exit }
      ($0 in seen) { print "line " NR ": " $0 " is listed twice"; exit }
      { seen[$0] = 1 }')"
    [ -z "$_km" ] || refuse "conf-keys.txt: $_km" "one harbor.toml key per line (contracts/pack.md)" || return 1
  fi

  # System terms (harbor#950): a workload's pack registers its own systems, so core's terms.tsv names no workload.
  # The core header, class `system` alone, a kebab id, never a core term and never one another installed pack declares:
  # bin/lint-name.sh reads all of them as one register. A term the private overlay holds never gets here: its rows are
  # leak patterns, and the leak gate above refuses the pack that names one.
  if [ -f "$WORK/stage/terms.d/$ID.tsv" ]; then
    _thdr="$(grep -v '^#' "$ROOT/standards/naming/terms.tsv" | awk 'NF { print; exit }')"
    awk -F'\t' '!/^#/ && NF && $1 != "id" { print $1 }' "$ROOT/standards/naming/terms.tsv" > "$WORK/terms.core"
    : > "$WORK/terms.other"
    for _f in "$T"/terms.d/*.tsv; do
      [ -f "$_f" ] && [ "$_f" != "$T/terms.d/$ID.tsv" ] || continue
      awk -F'\t' -v n="${_f##*/}" '!/^#/ && NF && $1 != "id" { print $1 "\tthe installed pack " n }' "$_f" >> "$WORK/terms.other"
    done
    _tm="$(tr -d '\r' < "$WORK/stage/terms.d/$ID.tsv" | awk -F'\t' -v h="$_thdr" -v core="$WORK/terms.core" -v other="$WORK/terms.other" '
      BEGIN { while ((getline l < core) > 0) c[l] = 1; while ((getline l < other) > 0) { split(l, o, "\t"); p[o[1]] = o[2] } }
      function out(m) { print m; done = 1; exit }
      /^[ \t]*#/ || /^[ \t]*$/ { next }
      !hdr { if ($0 != h) out("its header is not the core terms.tsv header"); hdr = 1; nf = NF; next }
      NF != nf { out("line " NR " has " NF " columns, the header has " nf) }
      $1 !~ /^[a-z][a-z0-9]*(-[a-z0-9]+)*$/ { out("line " NR ": " $1 " is not a lowercase kebab term") }
      $2 != "system" { out("line " NR ": " $1 " has class " $2 ": a pack registers system terms only") }
      ($1 in c) { out("line " NR ": " $1 " is a core term") }
      ($1 in p) { out("line " NR ": " $1 " is declared by " p[$1]) }
      ($1 in seen) { out("line " NR ": " $1 " is listed twice") }
      { seen[$1] = 1 }
      END { if (!done && !hdr) print "it has no header row" }')"
    [ -z "$_tm" ] || refuse "terms.tsv: $_tm" "system rows in the columns of standards/naming/terms.tsv (contracts/pack.md)" || return 1
  fi

  # Check rows (harbor#1149): checks.md must compose into the ONE register beside core, the private layer and every OTHER
  # installed pack, so a duplicate id is refused here, by name, before anything is written. controls.tsv rides with it.
  if [ -f "$WORK/stage/checks.d/$ID.md" ]; then
    rm -rf "$WORK/ck"; mkdir -p "$WORK/ck"
    for _f in "$T"/checks.d/*.md; do
      if [ -f "$_f" ] && [ "${_f##*/}" != "$ID.md" ]; then cp "$_f" "$WORK/ck/"; fi
    done
    cp "$WORK/stage/checks.d/$ID.md" "$WORK/ck/$ID.md"
    _grc=0; sh "$SRC/check-registry-generate.sh" --core "$ROOT/docs/reference/checks.md" --packs "$WORK/ck" > /dev/null 2> "$WORK/ck.err" || _grc=$?
    if [ "$_grc" -ne 0 ]; then
      _gm="$(sed -n 's/^.*FAIL[: ]*//p' "$WORK/ck.err" | head -n 1 | sed "s|$WORK/ck/|checks.d/|g")"
      refuse "checks.md does not compose into the register (exit $_grc): ${_gm:-see sh bin/check-registry-generate.sh}" \
        "fix checks.md in the pack, or the id it repeats; the shape is contracts/private-layer.md checks.md"
      return 1
    fi
  fi
  if [ -f "$WORK/stage/checks.d/$ID.controls.tsv" ]; then
    [ -f "$WORK/stage/checks.d/$ID.md" ] || refuse "controls.tsv without checks.md: a control row names a check" || return 1
    awk -F'|' '{ sub(/\r$/, "") } NR == 1 && index($0, "\357\273\277") == 1 { $0 = substr($0, length("\357\273\277") + 1) }
      /^## / { p = ($0 ~ /^## Register/) } p && /^\| `[a-z0-9.-]+` \|/ { id = $2; gsub(/[` ]/, "", id); print "check." id }' \
      "$WORK/stage/checks.d/$ID.md" > "$WORK/ctl.ids"
    _hdr="$(grep -v '^#' "$ROOT/standards/naming/controls.tsv" | awk 'NF { print; exit }')"
    _cm="$(tr -d '\r' < "$WORK/stage/checks.d/$ID.controls.tsv" | awk -F'\t' -v h="$_hdr" -v ids="$WORK/ctl.ids" '
      BEGIN { while ((getline l < ids) > 0) ok[l] = 1; nh = split(h, hc, "\t") }
      /^#/ || /^[ \t]*$/ { next }
      !seen++ { if ($0 != h) { print "its header is not the core controls.tsv header"; exit }; next }
      NF != nh { print "line " NR " has " NF " columns, not " nh; exit }
      !($1 in ok) { print "line " NR ": " $1 " is not check.<id> of a row in checks.md"; exit }')"
    [ -z "$_cm" ] || refuse "controls.tsv: $_cm" "the shape is standards/naming/controls.tsv" || return 1
  fi

  # Never overwrite what this pack did not write: core files, another pack's files, the operator's. One exception, the
  # pack move (harbor#1149): a skill core installed and no longer ships is released to the pack, but only while its bytes
  # are still the ones core's manifest recorded, so an operator's edit is never taken.
  mf_rows "$ID" F > "$WORK/owned"; : > "$WORK/release"
  while IFS="$TAB" read -r _s _r; do
    if [ -e "$T/$_r" ] || [ -L "$T/$_r" ]; then
      awk -v r="$_r" '$0 == r { f = 1 } END { exit !f }' "$WORK/owned" && continue
      if core_released "$_r"; then printf '%s\n' "$_r" >> "$WORK/release"; continue; fi
      refuse "$_r already exists in the target and is not this pack's" || return 1
    fi
  done < "$WORK/plan"
  return 0
}

core_released() { # <rel>: a core skill file core no longer ships, unchanged since core wrote it
  case "$1" in skills/*/*) ;; *) return 1 ;; esac
  _cs="${1#skills/}"; _cs="${_cs%%/*}"
  [ ! -e "$ROOT/skills/$_cs" ] && [ ! -e "$ROOT/vendor/skills/$_cs" ] || return 1
  _cb="$(il_mf_blob "$T" "$1")"
  [ -n "$_cb" ] && [ "$(il_blob "$T/$1")" = "$_cb" ]
}

# Core's manifest stops naming what a pack took over, so install-drift and remove each see one owner.
release_core() {
  [ -s "$WORK/release" ] && [ -f "$T/.harbor-manifest" ] || return 0
  awk -F'\t' "$_IL_MF_AWK"' NR == FNR { r[$0] = 1; next } /^#/ || !(rel($0) in r)' \
    "$WORK/release" "$T/.harbor-manifest" > "$T/.harbor-manifest.pack.$$" && mv -f "$T/.harbor-manifest.pack.$$" "$T/.harbor-manifest"
  log_note "$ID: took over $(wc -l < "$WORK/release" | tr -d ' ') file(s) core no longer ships"
}

# The installed register is core + private + every installed pack's fragment: recompose bin/docs/reference/checks.md when the pack's
# check rows came or went. A target with no bin/docs/reference/checks.md has no runtime yet, and runtime-install composes it then.
recompose() {
  [ -f "$T/bin/docs/reference/checks.md" ] || return 0
  _crc=0; sh "$SRC/check-registry-generate.sh" --core "$ROOT/docs/reference/checks.md" --packs "$T/checks.d" > "$WORK/checks.md" 2> "$WORK/recompose.err" || _crc=$?
  if [ "$_crc" -ne 0 ]; then
    log_fail "$ID: the register does not recompose (exit $_crc): $(sed -n 's/^.*FAIL[: ]*//p' "$WORK/recompose.err" | head -n 1)"
    log_fix "sh $SRC/check-registry-generate.sh --packs '$T/checks.d'   # names the line"
    return 1
  fi
  if ! cmp -s "$WORK/checks.md" "$T/bin/docs/reference/checks.md"; then
    cp "$WORK/checks.md" "$T/bin/docs/reference/checks.md.pack.$$" && chmod "$(stat_mode "$T/bin/docs/reference/checks.md")" "$T/bin/docs/reference/checks.md.pack.$$" && mv -f "$T/bin/docs/reference/checks.md.pack.$$" "$T/bin/docs/reference/checks.md"
  fi
}
stat_mode() { [ -x "$1" ] && echo 755 || echo 644; }

install_one() { # <id> - returns 1 when the pack was skipped
  plan_one "$1" || return 1
  _n="$(wc -l < "$WORK/plan" | tr -d ' ')"
  _nr="$(wc -l < "$WORK/release" | tr -d ' ')"
  if [ "$IL_APPLY" -eq 0 ]; then
    log_ok "would install $ID ($NAME $VER, $_n files) at $COMMIT$([ "$_nr" -eq 0 ] || printf ', taking over %s file(s) core no longer ships' "$_nr")"
    return 0
  fi
  # Directories this run creates, shallowest first, so remove can take them back.
  : > "$WORK/dirs"
  while IFS="$TAB" read -r _s _r; do
    _d="${_r%/*}"
    while [ "$_d" != "$_r" ] && [ "$_d" != . ]; do printf '%s\n' "$_d"; _x="${_d%/*}"; [ "$_x" != "$_d" ] || break; _d="$_x"; done
  done < "$WORK/plan" | awk '{ print length($0) "\t" $0 }' | sort -n | cut -f2- | awk '!s[$0]++' > "$WORK/dirs.all"
  while IFS= read -r _d; do [ -d "$T/$_d" ] || printf '%s\n' "$_d" >> "$WORK/dirs"; done < "$WORK/dirs.all"
  mf_rows "$ID" D | awk 'NF' >> "$WORK/dirs"
  awk '!s[$0]++' "$WORK/dirs" > "$WORK/dirs.u"
  while IFS= read -r _d; do mkdir -p "$T/$_d"; done < "$WORK/dirs.all"
  while IFS="$TAB" read -r _s _r; do
    cp "$WORK/stage/$_r" "$T/$_r.pack.$$" && chmod "$([ -x "$WORK/stage/$_r" ] && echo 755 || echo 644)" "$T/$_r.pack.$$" && mv -f "$T/$_r.pack.$$" "$T/$_r"
  done < "$WORK/plan"
  # Files an earlier install wrote and this one no longer carries.
  while IFS= read -r _r; do
    awk -F'\t' -v r="$_r" '$2 == r { f = 1 } END { exit !f }' "$WORK/plan" || rm -f "$T/$_r"
  done < "$WORK/owned"
  mkdir -p "$MFD"
  {
    printf '# repo\t%s\n# name\t%s\n# version\t%s\n# commit\t%s\n' "$ID" "$NAME" "$VER" "$COMMIT"
    cut -f2 "$WORK/plan" | sort | awk '{ print "F\t" $0 }'
    awk '{ print "D\t" $0 }' "$WORK/dirs.u"
  } > "$MFD/$ID.tsv.tmp.$$" && mv -f "$MFD/$ID.tsv.tmp.$$" "$MFD/$ID.tsv"
  release_core
  log_ok "installed $ID ($NAME $VER, $_n files) at $COMMIT"
  if awk -F'\t' '$2 ~ /^checks\.d\// { f = 1 } END { exit !f }' "$WORK/plan" || awk '$0 ~ /^checks\.d\// { f = 1 } END { exit !f }' "$WORK/owned"; then
    recompose || return 1
  fi
}

remove_one() { # <id>
  ID="$1"
  [ -f "$MFD/$ID.tsv" ] || { log_fail "skipped $ID: no install manifest in $T"; log_fix "sh $0 list $(il_spell)"; return 1; }
  if [ "$IL_APPLY" -eq 0 ]; then log_ok "would remove $ID ($(mf_rows "$ID" F | wc -l | tr -d ' ') files)"; return 0; fi
  _hadck=0; mf_rows "$ID" F | awk '$0 ~ /^checks\.d\// { f = 1 } END { exit !f }' && _hadck=1
  mf_rows "$ID" F | while IFS= read -r _r; do [ -z "$_r" ] || rm -f "$T/$_r"; done
  mf_rows "$ID" D | awk '{ print length($0) "\t" $0 }' | sort -rn | cut -f2- | while IFS= read -r _d; do
    [ -z "$_d" ] || rmdir "$T/$_d" 2>/dev/null || :
  done
  rm -f "$MFD/$ID.tsv"
  # checks.d is shared by every pack, so only the pack that created it holds its D row: the last pack out takes it if empty.
  if rmdir "$MFD" 2>/dev/null; then rmdir "$T/checks.d" "$T/shims.d" "$T/conf-keys.d" "$T/terms.d" 2>/dev/null || :; fi
  log_ok "removed $ID"
  if [ "$_hadck" -eq 1 ]; then recompose || return 1; fi
}

RC=0
case "$VERB" in
  install)
    if [ -z "$IDS" ]; then
      IDS="$(sh "$SRC/scope-roots.sh" --conf packs 2>/dev/null | tr '\n' ' ')" || IDS=''
      [ -n "$IDS" ] || { log_note 'harbor.toml lists no packs: nothing to install'; log_end || :; exit 0; }
    fi
    for _i in $IDS; do install_one "$_i" || RC=1; done ;;
  remove)
    [ -n "$IDS" ] || il_usage_error 'remove needs a repo id'
    for _i in $IDS; do remove_one "$_i" || RC=1; done ;;
  list)
    for _m in "$MFD"/*.tsv; do
      [ -f "$_m" ] || continue
      awk -F'\t' '$1 == "# name" { n = $2 } $1 == "# version" { v = $2 } $1 == "# commit" { c = $2 } $1 == "# repo" { r = $2 }
                  $1 == "F" { f++ } END { printf "%s\t%s\t%s\t%s\t%d files\n", r, n, v, substr(c, 1, 12), f }' "$_m"
    done
    for _i in $(sh "$SRC/scope-roots.sh" --conf packs 2>/dev/null || :); do
      [ -f "$MFD/$_i.tsv" ] || printf '%s\tnot installed\n' "$_i"
    done ;;
esac
log_end || :
exit "$RC"
