#!/bin/zsh
# Rebuild the debug app (unsigned) and relaunch it against a throwaway data
# folder, so testing never touches the real board.
#   scripts/dev-run.sh [--keep-data] [extra app arguments…]
set -e
cd "$(dirname "$0")/.."
DATA="${KANBAN_DEV_DATA:-$TMPDIR/InternshipKanban-dev-data}"
# Quit the running copy first: it flushes its board on quit.
pkill -f "Kanban Board.app/Contents/MacOS" && sleep 1 || true
if [[ "$1" == "--keep-data" ]]; then shift; else rm -rf "$DATA"; fi
mkdir -p "$DATA" build
xcodegen generate -q
xcodebuild -project InternshipKanban.xcodeproj -scheme InternshipKanban -configuration Debug \
  -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO build > build/build.log 2>&1 \
  || { grep -E "error:" build/build.log | sort -u; exit 1; }
grep -E "(error|warning): " build/build.log | sort -u || true
KANBAN_DRAG_LOG=1 KANBAN_DATA_DIR="$DATA" nohup "build/DerivedData/Build/Products/Debug/Kanban Board.app/Contents/MacOS/Kanban Board" "$@" > build/app.log 2>&1 &
echo "running; data in $DATA"
