#!/usr/bin/env sh
# contracts/member-files.txt against what the floor wires (harbor#1278): a guard the dispatcher can't find is a blocked call, or a silent gap.
. "$(dirname "$0")/../../lib/core.sh"; t_init
L="$T_ROOT/contracts/member-files.txt"
rows() { sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^[[:space:]]*$/d' "$L"; }
names() { rows | awk '{ print ($2 != "" ? $2 : $1) }' | sed 's|.*/||'; }

t_section "the shape"
t_eq "one or two words a row" 0 "$(rows | awk 'NF > 2' | wc -l | tr -d ' ')"
t_eq "no two rows land on one name" '' "$(names | sort | uniq -d)"
t_eq "a repo path, never an absolute one" 0 "$(rows | grep -c '^/')"

t_section "the guard table is the generator's output"
t_eq "contracts/member-guards.tsv matches floor_hooks" "$(sh "$T_ROOT/bin/member-dispatch.sh" --guard-table "$T_ROOT/bin/admission-install.sh")" "$(grep -v '^#' "$T_ROOT/contracts/member-guards.tsv")"
t_has "it lands beside the dispatcher" "$(rows)" 'contracts/member-guards.tsv member-guards.tsv'

t_section "each row exists, or a lane owns it"
LANES='bin/member-dispatch.sh bin/member-post.sh bin/member-integrity.sh bin/hub-tier.sh bin/hub-sync.sh bin/member-session.sh bin/hub-approval.sh bin/hub-board.sh bin/hub-events.sh bin/member-update.sh'
rows | while read -r s _; do
  [ -f "$T_ROOT/$s" ] && continue
  case " $LANES " in *" $s "*) ;; *) echo "$s" ;; esac
done > "$T_TMP/missing"
t_eq "no row names a file nobody is building" '' "$(cat "$T_TMP/missing")"
for s in $LANES; do t_has "$s is listed" "$(rows)" "$s"; done

t_section "derived from the floor's own wiring"
# floor_hooks is the table the user-tier floor installs: event;matcher;argv. Each script word of it must reach the managed root.
sed -n "/^floor_hooks() { cat <<'ROWS'/,/^ROWS\$/p" "$T_ROOT/bin/admission-install.sh" | grep -E '^[A-Z][A-Za-z]+;' | cut -d';' -f3 | tr ' ' '\n' | grep '\.sh$' | sort -u > "$T_TMP/wired"
t_eq "the table was read" 1 "$([ "$(wc -l < "$T_TMP/wired" | tr -d ' ')" -ge 6 ] && echo 1)"
OPTIONAL='admission-stop.sh admission-integrity.sh event-hook.sh'
while IFS= read -r g; do
  case " $OPTIONAL " in *" $g "*) continue ;; esac
  case "$g" in *-confirm*|context-*|session-*|ci-*) continue ;; esac
  names | grep -qxF "$g" && t_pass || t_fail "the floor wires $g, and contracts/member-files.txt doesn't carry it"
done < "$T_TMP/wired"
for f in library-admission.sh library-log.sh admission-decide.sh controls.tsv admission-normalize.awk secret access.sh scope-roots.sh roots.tsv library-hub.sh \
         hub.sh pack.sh library-pack-version.sh deploy-install-lib.sh harbor pack-frontmatter-keys.txt skill-pack-frontmatter-keys.txt; do
  names | grep -qxF "$f" && t_pass || t_fail "$f is read by what is listed, and isn't listed"
done
t_eq "a guard sources by its own folder, so flat is the right shape" 1 "$(grep -c '^\. "$DIR/library-admission.sh"$' "$T_ROOT/bin/admission-bash.sh")"
t_done
