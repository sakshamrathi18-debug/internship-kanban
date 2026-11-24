#!/bin/zsh
# shoot.sh <out.png> <board: full|empty|seed|corrupt|newer> <appearance> [demo] [window size] [window title]
OUT=$1; BOARD=$2; LOOK=$3; DEMO=$4; SIZE=${5:-1200x760}; TITLE=${6:-Kanban Board}
cd "$(dirname "$0")/../.."
DATA=$(mktemp -d)/data
python3 scripts/design/demo_board.py "$DATA" "$BOARD"
APP="build/DerivedData/Build/Products/Debug/Kanban Board.app/Contents/MacOS/Kanban Board"
KANBAN_DATA_DIR="$DATA" KANBAN_APPEARANCE="$LOOK" KANBAN_DEMO="$DEMO" KANBAN_WINDOW_SIZE="$SIZE" \
  "$APP" -ApplePersistenceIgnoreState YES >/dev/null 2>&1 &
PID=$!
sleep ${WAIT:-3}
build/capture_windows $PID "$OUT" "$TITLE"
kill $PID 2>/dev/null; wait $PID 2>/dev/null
