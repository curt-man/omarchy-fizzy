#!/usr/bin/env bash
# Assemble a Quickshell config folder outside the repo.
#
# Quickshell only imports modules from inside its own config folder, so the
# plugin's QML and the shell's Commons/Ui have to sit beside a shell.qml.
# Omarchy refuses a plugin folder containing any symlink — one could point a
# plugin that has landed in the trusted directory at anything on disk — so the
# folder is built somewhere else and links back in.
set -euo pipefail
cd "$(dirname "$0")"
repo="$(cd .. && pwd)"

. ./stage.sh
rm -rf "$STAGE"; mkdir -p "$STAGE"

ln -sfn /usr/share/omarchy/shell/Commons "$STAGE/Commons"
ln -sfn /usr/share/omarchy/shell/Ui "$STAGE/Ui"

# fizzy-fetch and its fixtures too: without them beside the QML the harness
# cannot run a request at all, so --demo data never arrives and the window
# renders empty for no visible reason.
for f in "$repo"/*.qml "$repo"/Model.js "$repo"/fizzy-fetch "$repo"/fizzy-demo.json; do
  ln -sfn "$f" "$STAGE/$(basename "$f")"
done
ln -sfn "$(pwd)/shell.qml" "$STAGE/shell.qml"
echo "$STAGE"
