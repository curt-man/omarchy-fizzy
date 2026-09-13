#!/usr/bin/env bash
# Everything that can be checked without a compositor.
#
#   dev/test.sh
#
# Three passes: the pure helpers in Model.js, the demo fixtures against the
# shapes the QML reads off them, and qmllint over every .qml file. What is left
# after that is how it looks, which is what dev/showcase.sh is for.
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0

echo "── Model.js"
node dev/test-model.js || fail=1

echo "── fixtures"
node dev/test-demo.js || fail=1

echo "── qmllint"
LINT=$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)
if [ -x "$LINT" ]; then
  # The shell's modules live outside the repo; qmllint needs them on the import
  # path or every qs.Ui type reads as unknown and the real findings are buried.
  IMPORTS=$(mktemp -d)
  trap 'rm -rf "$IMPORTS"' EXIT
  ln -sfn /usr/share/omarchy/shell "$IMPORTS/qs"

  # Unqualified access is how a plugin reads its own root properties here;
  # QProcess/DataStreamParser come from Quickshell rather than from Qt's own
  # module index; and Repeater.itemAt() is declared as QQuickItem, so every
  # property a delegate adds reads as missing. None of the three is a finding.
  for file in *.qml; do
    out=$("$LINT" -I "$IMPORTS" "$file" 2>&1 \
      | grep -E '^(Warning|Error):' \
      | grep -vE 'Unqualified access|not found on type "QObject"|not found on type "QQuickItem"|QProcess::ExitStatus|DataStreamParser' || true)
    [ -z "$out" ] || { echo "$out"; fail=1; }
  done
  echo "  $(ls *.qml | wc -l) files"
else
  echo "  qmllint not found — skipped"
fi

[ "$fail" -eq 0 ] && echo "ok" || { echo "FAILED" >&2; exit 1; }
