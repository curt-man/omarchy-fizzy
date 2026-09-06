#!/usr/bin/env bash
# Generate the README images, from fixtures, in one pass.
#
#   dev/showcase.sh [outdir]        # default: the repo root
#
# Nothing of yours ends up in an image, and nothing of yours is touched to make
# one: the harness is its own Quickshell instance running the panel with
# `demo` on, so fizzy-fetch answers every read from fizzy-demo.json and refuses
# every write. No token is read, no instance is contacted, and your shell.json
# is never opened. The invented people have no avatar_url at all, so not even a
# picture is fetched — every seat is an initials disc drawn locally.
set -euo pipefail
cd "$(dirname "$0")"

OUT="$(cd "${1:-..}" && pwd)"
. ./stage.sh

for tool in qs jq; do
  command -v "$tool" >/dev/null || { echo "showcase: $tool is required" >&2; exit 1; }
done

./run.sh >/dev/null
trap 'pkill -x -f "qs -p $STAGE/shell.qml" 2>/dev/null || true' EXIT

ipc() { qs -p "$STAGE/shell.qml" ipc call dev "$@" >/dev/null; }
shot() { ipc shot "$1"; sleep 0.9; [ -s "$1" ] || { echo "showcase: no image at $1" >&2; exit 1; }; }

# A column with work in it — the picture that has to say in one glance what
# this is. It is also the one that shows a card with more people on it than
# the row has seats for.
ipc filter demo-col-2
sleep 1
shot "$OUT/showcase-board.png"

# One card, open: the moves, the steps, who is on it, its tags.
ipc open 388
sleep 1.2
shot "$OUT/showcase-card.png"

# The same card, scrolled to the conversation.
ipc scroll 10
sleep 1.2
shot "$OUT/showcase-comments.png"

# Everything the widget can be told.
ipc page settings
sleep 1.2
shot "$OUT/showcase-settings.png"

# Where you land with no board chosen.
ipc page boards
sleep 1.2
shot "$OUT/showcase-boards.png"

echo "wrote showcase-*.png to $OUT"
