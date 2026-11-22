#!/bin/sh
# Model-checks HyperHold.tla, one property at a time, and compares with the known findings.
# Usage: .claude/skills/model-check-hyper-hold/check.sh [PROPERTY...]
# Exit 0: every result matches the baseline below. Exit 1: a new failure, or a known finding now passes.
set -eu

dir=$(cd "$(dirname "$0")" && pwd)
jar=${TLA2TOOLS:-$HOME/.local/share/tlaplus/tla2tools-1.7.4.jar}
if [ ! -f "$jar" ]; then
  echo "TLA+ tools missing at $jar. Install (one time, 2.2 MB):" >&2
  echo "  mkdir -p ~/.local/share/tlaplus && curl -fsSL -o ~/.local/share/tlaplus/tla2tools-1.7.4.jar https://github.com/tlaplus/tlaplus/releases/download/v1.7.4/tla2tools.jar" >&2
  exit 2
fi

# Properties the current code is known to break (see SKILL.md, Findings). Update both together.
known=""
all="TypeOK GuideHidesAfterRelease HotkeyNeverFlashes GuideShowsOnLongHold"
props=${*:-$all}

work=$(mktemp -d "${TMPDIR:-/tmp}/hyperhold.XXXXXX")
trap 'rm -rf "$work"' EXIT
cp "$dir/HyperHold.tla" "$work/"

status=0
for p in $props; do
  printf 'SPECIFICATION Spec\nCONSTANTS MaxPresses = 2\n          DelayPolls = 2\nINVARIANT %s\n' "$p" > "$work/$p.cfg"
  out="$work/$p.out"
  (cd "$work" && java -XX:+UseParallelGC -cp "$jar" tlc2.TLC -workers 1 -deadlock \
      -config "$p.cfg" -metadir "$work/meta-$p" HyperHold.tla > "$out" 2>&1) || true
  case " $known " in *" $p "*) expect=fail ;; *) expect=pass ;; esac
  if grep -q "is violated" "$out"; then
    got=fail
  elif grep -q "No error has been found" "$out"; then
    got=pass
  else
    echo "== $p: TLC did not finish"; cat "$out"; status=1; continue
  fi
  states=$(grep -Eo '[0-9,]+ distinct states found' "$out" | head -1 || true)
  if [ "$got" = fail ]; then
    [ "$expect" = fail ] && tag="FAIL (known finding)" || { tag="FAIL (NEW)"; status=1; }
    echo "== $p: $tag"
    sed -n '/is violated/,/^Finished\|distinct states found/p' "$out" | grep -v '^Finished'
  else
    [ "$expect" = pass ] && tag="pass" || { tag="pass (known finding no longer reproduces: update SKILL.md and check.sh)"; status=1; }
    echo "== $p: $tag ($states)"
  fi
done
exit $status
