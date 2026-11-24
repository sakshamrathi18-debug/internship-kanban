#!/bin/zsh
# Builds a signed Release copy of Kanban Board and installs it into
# /Applications, so the desktop widget shows up in the widget gallery.
#
#   scripts/install.sh            build, install, launch
#   scripts/install.sh --dmg      also write build/KanbanBoard.dmg
#
# Needs: Xcode, and your (free) Apple ID added in Xcode › Settings › Accounts.
# The Team ID is read from Config/Signing.xcconfig, or detected from Xcode.
set -e
cd "$(dirname "$0")/.."

# --- Team ID -------------------------------------------------------------
TEAM=$(sed -n 's/^DEVELOPMENT_TEAM *= *\([A-Z0-9]\{10\}\).*/\1/p' Config/Signing.xcconfig)
if [[ -z "$TEAM" ]]; then
  # Xcode keeps the teams of each signed-in account in its preferences.
  TEAM=$(defaults export com.apple.dt.Xcode - 2>/dev/null | plutil -extract IDEProvisioningTeamByIdentifier json -o - - 2>/dev/null \
    | python3 -c 'import json,sys; d=json.load(sys.stdin); ids=[t["teamID"] for teams in d.values() for t in teams]; print(ids[0] if ids else "")' 2>/dev/null || true)
fi
if [[ -z "$TEAM" ]]; then
  TEAM=$(security find-certificate -c "Apple Development" -p 2>/dev/null | openssl x509 -noout -subject 2>/dev/null \
    | sed -n 's/.*OU *= *\([A-Z0-9]\{10\}\).*/\1/p' | head -1)
fi
if [[ -z "$TEAM" ]]; then
  echo "No signing team found. In Xcode: Settings › Accounts › + › Apple ID, then run this again."
  exit 1
fi
echo "Signing with team $TEAM (App Group $TEAM.com.sakshamrathi.InternshipKanban)"

# --- Build ---------------------------------------------------------------
xcodegen generate -q
xcodebuild -project InternshipKanban.xcodeproj -scheme InternshipKanban -configuration Release \
  -derivedDataPath build/Release DEVELOPMENT_TEAM="$TEAM" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \
  build > build/release.log 2>&1 || { grep -E "error:" build/release.log | sort -u; echo "Build failed (full log: build/release.log)"; exit 1; }
APP="build/Release/Build/Products/Release/Kanban Board.app"
codesign --verify --deep --strict "$APP"
echo "Built and verified: $APP"

# --- Install -------------------------------------------------------------
osascript -e 'tell application id "com.sakshamrathi.InternshipKanban" to quit' >/dev/null 2>&1 || true
sleep 1
# Earlier versions were called "Internship Kanban"; same app, same data.
rm -rf "/Applications/Internship Kanban.app" "/Applications/Kanban Board.app"
ditto "$APP" "/Applications/Kanban Board.app"
# Register the app and its widget with the system, then open it once.
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/Kanban Board.app" >/dev/null 2>&1 || true
open "/Applications/Kanban Board.app"
echo "Installed to /Applications/Kanban Board.app"

# --- Optional DMG --------------------------------------------------------
if [[ "$1" == "--dmg" ]]; then
  STAGE=$(mktemp -d)
  ditto "$APP" "$STAGE/Kanban Board.app"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Kanban Board" -srcfolder "$STAGE" -ov -format UDZO build/KanbanBoard.dmg >/dev/null 2>&1
  rm -rf "$STAGE"
  echo "Disk image: build/KanbanBoard.dmg"
fi
