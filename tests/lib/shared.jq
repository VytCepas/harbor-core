# tests/lib/shared.jq — expand shapes.jsonl and benign.jsonl into rows for guard $g.
# A shape rewrites each of the guard's representative commands (guards.jsonl `reps`, a command,
# or {cmd, want} when the tier answers otherwise); an exemption replaces one row's verdict.
def expect($rel; $w):
  if $rel == "same" then $w
  elif $rel == "allow" then "allow"
  elif $rel == "no-human" then (if $w == "ask" then "deny" else $w end)
  else "BAD-EXPECT:" + $rel end;
def fill($form; $cmd):
  ($cmd | split(" ")) as $p
  | $form | gsub("\\{cmd\\}"; $cmd) | gsub("\\{bin\\}"; $p[0])
  | gsub("\\{BIN\\}"; ($p[0] | ascii_upcase)) | gsub("\\{args\\}"; ($p[1:] | join(" ")));

($reg[] | select(.guard == $g)) as $r
| ($ex | map(select(.guard == $g) | {key: .id, value: .}) | from_entries) as $exm
| ( [ $shapes[] as $s
      | ($s.reps // ["deny", "ask", "allow"])[] as $rep
      | select($r.reps[$rep] != null)
      | select($s.posture == null or $r.posture != null)
      | ($r.reps[$rep] | if type == "object" then . else {cmd: ., want: $rep} end) as $rp
      | { id: "shape:\($s.shape)/\($rep)", rule: "shared",
          want: expect($s.expect; $rp.want), cmd: fill($s.form // "{cmd}"; $rp.cmd) }
        + (if $s.pad then {pad: $s.pad} else {} end)
        + (if $s.ctx then {ctx: $s.ctx} else {} end)
        + (if $s.fixture then {fixture: $s.fixture} else {} end)
        + (if $s.posture then {env: {($r.posture): $s.posture}} elif $s.env then {env: $s.env} else {} end) ]
  + [ $benign[] | {id: "benign:\(.id)", rule: "shared", want: "allow"} + del(.id, .why) ] )[]
| . as $row
| ($exm[$row.id] // null) as $e
| if $e then $row + {want: $e.want, why: $e.why} + (if $e.todo then {todo: $e.todo} else {} end) else $row end
