#!/bin/zsh
# Builds Kanban Board for iPhone, signs it with your free Apple ID team, and
# installs it on the iPhone connected to this Mac (cable, or Wi-Fi once paired).
#
#   scripts/install-iphone.sh
#
# With a free Apple ID, Apple lets the install run for 7 days. Run this again
# any time to renew it: your board is kept (it lives in the app's App Group).
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=$(grep -E '^DEVELOPMENT_TEAM *=' Config/Signing.xcconfig | sed 's/.*= *//' | tr -d ' ')
[[ -n "$TEAM" ]] || { echo "Set DEVELOPMENT_TEAM in Config/Signing.xcconfig first."; exit 1; }

# Find a real (not simulated) iPhone.
JSON=$(mktemp)
xcrun devicectl list devices --json-output "$JSON" >/dev/null 2>&1 || true
read -r DEVICE UDID NAME <<<"$(python3 - "$JSON" <<'EOF'
import json, sys
try:
    devices = json.load(open(sys.argv[1]))["result"]["devices"]
except Exception:
    devices = []
for d in devices:
    hw = d.get("hardwareProperties", {})
    if hw.get("reality") == "physical" and hw.get("platform") == "iOS":
        print(d["identifier"], hw.get("udid", ""), d.get("deviceProperties", {}).get("name", "iPhone").replace(" ", "_"))
        break
EOF
)"
rm -f "$JSON"

if [[ -z "${DEVICE:-}" ]]; then
  cat <<'MSG'
No iPhone found. Connect it with a cable, unlock it, and tap "Trust" if it asks.

First time only, on the iPhone:
  1. Settings › Privacy & Security › Developer Mode → On (the phone restarts).
     If Developer Mode isn't listed yet, keep the phone connected and open
     Xcode › Window › Devices and Simulators once; then it appears.
MSG
  exit 1
fi

echo "Building for ${NAME//_/ } (team $TEAM)…"
xcodegen generate -q
mkdir -p build
xcodebuild -project InternshipKanban.xcodeproj -scheme KanbanBoardiOS -configuration Release \
  -destination "id=$UDID" -derivedDataPath build/iPhone \
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  DEVELOPMENT_TEAM="$TEAM" build > build/iphone.log 2>&1 \
  || { grep -E "error:" build/iphone.log | sort -u; echo "Full log: build/iphone.log"; exit 1; }

APP="build/iPhone/Build/Products/Release-iphoneos/Kanban Board.app"
echo "Installing…"
xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null
if ! xcrun devicectl device process launch --device "$DEVICE" com.sakshamrathi.KanbanBoard >/dev/null 2>&1; then
  cat <<'MSG'
Installed, but iOS won't open it until you trust the developer (first time only):
  Settings › General › VPN & Device Management › your Apple ID › Trust
Then open Kanban Board from the home screen.
MSG
  exit 0
fi
echo "Done. Kanban Board is open on your iPhone."
echo "Free Apple ID installs last 7 days; run this script again to renew."
