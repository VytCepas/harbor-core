# tests/lib/linux-sim.sh — Linux, simulated on a Mac (harbor#618). Source after t_init.
# GNU coreutils' stat, as Linux has it (harbor#618): `-f` is --file-system, so `stat -f '%u' f`
# prints filesystem fields and fails on the operand '%u'; `-c` answers. The -c branch asks the
# real stat, whichever dialect this host has.
gnu_stat_stub() { # <dir> — writes <dir>/stat
  mkdir -p "$1"
  cat > "$1/stat" <<'STUB'
#!/bin/sh
case "$1" in
  -f) printf '  File: "%s"\n    ID: 0 Namelen: 255 Type: ext2/ext3\n' "$3"; exit 1 ;;
  -c) case "$2" in
        # GNU %a keeps the setuid/setgid/sticky digit (4755): BSD %Mp%Lp does, minus GNU's leading zeros.
        %a) /usr/bin/stat -c %a "$3" 2>/dev/null || { /usr/bin/stat -f %Mp%Lp "$3" | sed 's/^0*\([0-9]\)/\1/'; } ;;
        %u|%Y|%s) case "$2" in %u) b=%u ;; %Y) b=%m ;; *) b=%z ;; esac
          /usr/bin/stat -c "$2" "$3" 2>/dev/null || /usr/bin/stat -f "$b" "$3" ;;
        *) exit 1 ;;
      esac ;;
  *) exit 1 ;;
esac
STUB
  chmod +x "$1/stat"
}

# A PATH directory holding every tool on this PATH except the macOS-only ones named, so a Linux
# code path can run on a Mac. Links, never copies; the first match on PATH wins, as it would.
linux_path() { # <dir> <tool-to-leave-out>...
  _lp="$1"; shift; mkdir -p "$_lp"
  for _d in $(printf '%s' "$PATH" | tr ':' ' '); do
    for _x in "$_d"/*; do
      _n="${_x##*/}"
      case " $* " in *" $_n "*) continue ;; esac
      [ -x "$_x" ] && [ ! -e "$_lp/$_n" ] && ln -s "$_x" "$_lp/$_n" 2>/dev/null || :
    done
  done
}
