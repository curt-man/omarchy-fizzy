#!/usr/bin/env bash
# Photograph what the harness is drawing.
#
#   dev/shot.sh out.png              # as it is
#   dev/shot.sh out.png 388          # opening that card first
set -euo pipefail
cd "$(dirname "$0")"
. ./stage.sh
OUT="$(realpath -m "${1:-/tmp/fizzy.png}")"

if [ $# -ge 2 ]; then
  qs -p "$STAGE/shell.qml" ipc call dev open "$2" >/dev/null
  sleep 0.6
fi
qs -p "$STAGE/shell.qml" ipc call dev shot "$OUT" >/dev/null
sleep 0.8
[ -s "$OUT" ] && echo "$OUT" || { echo "no image written; see $STAGE/harness.log" >&2; exit 1; }
