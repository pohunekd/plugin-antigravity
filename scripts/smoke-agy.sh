#!/usr/bin/env bash
# Antigravity CLI runtime smoke script (V3 + V5-core): runs inside the kit's
# live isolated root after the generic smoke checks pass.
#
# Checks:
# - V3: descriptor [min, below) equals compat/compatibility-lock.json supported block;
# - V3: installed `agy --version` matches the locked release;
# - V5-core: the fresh unauthenticated smoke session reaches activity=blocked
#   on the sign-in screen and refuses `pohunek session input` with
#   `session_input_blocked` (`refuse_while_blocked = true`).
set -euo pipefail

if [ -z "${POHUNEK_SMOKE_SESSION:-}" ]; then
  echo "smoke-agy.sh: POHUNEK_SMOKE_SESSION is unset" >&2
  exit 1
fi
session="$POHUNEK_SMOKE_SESSION"

here="$(cd "$(dirname "$0")/.." && pwd)"
tmpdir="${TMPDIR:-$here/.tmp-smoke-agy}"
mkdir -p "$tmpdir"
out="$(mktemp "$tmpdir/smoke-agy-out.XXXXXX")"
trap 'rm -f "$out"; [ -n "${TMPDIR:-}" ] || rm -rf "$tmpdir"' EXIT

fail() { echo "smoke-agy: FAIL $1" >&2; [ -n "${2:-}" ] && printf '%s\n' "$2" >&2; exit 1; }
ok() { echo "smoke-agy: ok $1"; }

# V3: the descriptor's [min, below) range equals the lock's supported block.
read -r min below < <(
  python3 -c '
import sys, tomllib
doc = tomllib.loads(open(sys.argv[1], encoding="utf-8").read())
vp = doc["runtime"]["version_probe"]
print(vp["min"], vp["below"])
' "$here/package/runtime.toml"
)
read -r lock_min lock_below locked < <(
  python3 -c '
import json, sys
doc = json.load(open(sys.argv[1], encoding="utf-8"))
print(doc["supported"]["min"], doc["supported"]["below"], doc["upstream"]["release"])
' "$here/compat/compatibility-lock.json"
)
[ "$min" = "$lock_min" ] || fail "lock-range" "min $min != lock $lock_min"
[ "$below" = "$lock_below" ] || fail "lock-range" "below $below != lock $lock_below"
ok "lock-range ($min / $below)"

# V3 version probe: the installed upstream answers with the locked release.
probed="$(agy --version)"
[ "$probed" = "$locked" ] || fail "version-probe" "got '$probed', want '$locked'"
ok "version-probe ($probed)"

activity_of() {
  pohunek session list --json >"$out" 2>&1 || fail "list" "$(cat "$out")"
  SID="$1" python3 -c 'import json,os,sys; print(next(s["activity"] for s in json.load(open(sys.argv[1]))["ok"] if s["id"] == os.environ["SID"]))' "$out"
}
screen_of() {
  pohunek session screen "$1" --json >"$out" 2>&1 || fail "screen" "$(cat "$out")"
  python3 -c 'import json,sys; print("\n".join(json.load(open(sys.argv[1]))["ok"]["visible_lines"]))' "$out"
}

# V5-core: an unauthenticated smoke session opens on the sign-in screen and
# reports activity=blocked; poll inside the script timeout budget.
activity=""
screen=""
end=$((SECONDS + 45))
while [ $SECONDS -lt $end ]; do
  activity="$(activity_of "$session")"
  screen="$(screen_of "$session")"
  if [ "$activity" = "blocked" ] && printf '%s' "$screen" | grep -q "Welcome to the Antigravity CLI"; then
    break
  fi
  sleep 1
done
[ "$activity" = "blocked" ] || fail "login-blocked" "activity=$activity (want blocked)"
printf '%s' "$screen" | grep -q "Welcome to the Antigravity CLI" || fail "login-frame" "sign-in banner not on screen"
ok "login-blocked"

# While blocked, session input must be refused with session_input_blocked.
if printf 'x\n' | pohunek session input "$session" --stdin >"$out" 2>&1; then
  fail "refusal" "session input accepted while blocked"
fi
grep -qi "session_input_blocked" "$out" || fail "refusal" "$(cat "$out")"
ok "refusal (session_input_blocked)"

ok "v5-core-done"
