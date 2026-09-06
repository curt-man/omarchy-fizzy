#!/usr/bin/env bash
# (Re)start the harness.
#
# It is its own Quickshell instance, so it neither reads nor writes the shell
# you are running — but it does draw a real layer-shell surface, because that
# is what the panel is. Expect it on screen while it is up.
#
# Restarted rather than hot-reloaded: Quickshell's reload prompt needs a real
# window, and failing to open one leaves IPC refusing queries.
set -euo pipefail
cd "$(dirname "$0")"

STAGE="$(./link.sh)"
# -x, so this matches the harness and not the shell running this script — a
# bare -f pattern also matches any command line that mentions the path, which
# includes the one asking for a screenshot.
pkill -x -f "qs -p $STAGE/shell.qml" 2>/dev/null || true
sleep 0.5

qs -p "$STAGE/shell.qml" >"$STAGE/harness.log" 2>&1 &

for _ in $(seq 1 60); do
  sleep 0.2
  if qs -p "$STAGE/shell.qml" ipc call dev state >/dev/null 2>&1; then
    echo "harness up — dev/shot.sh out.png"
    exit 0
  fi
done
echo "harness did not come up; see $STAGE/harness.log" >&2
tail -30 "$STAGE/harness.log" >&2
exit 1
