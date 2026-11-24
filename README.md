# Kanban Board

A calm, personal Kanban board for the summer-internship process, with a desktop widget.
macOS 14 or later, SwiftUI, no third-party code.

## Install (the easy way)

One-time setup (free; no paid Apple Developer account needed):

1. Install **Xcode** from the App Store and open it once.
2. **Xcode › Settings… › Accounts › + › Apple ID**, sign in. That creates your free "Personal Team".

Then, from this folder:

```bash
scripts/install.sh
```

That builds a signed copy, puts it in `/Applications/Kanban Board.app` and opens it.
`scripts/install.sh --dmg` also writes `build/KanbanBoard.dmg`.

## Add the widget

Right-click the desktop › **Edit Widgets…** › search **Kanban Board** › pick Small,
Medium or Large and drag it onto the desktop (or into Notification Centre).
The app must have been opened once from `/Applications` first.

- **Small**: In Progress count, To Do · On Hold · Done, % complete.
- **Medium**: "Now" (up to 3 In Progress, then To Do), each with a **→** button.
- **Large**: the whole board in miniature, 5 cards per column, "+N more".

**→** moves a card forward (To Do → In Progress → Done; On Hold → In Progress).
Clicking a card opens the app with it selected.

## Launch at login

Open the app › **Kanban Board › Settings… (⌘,)** › **Launch at login**.
(If macOS asks, approve it in System Settings › General › Login Items.)

## Using it

| | |
|---|---|
| Add | "+ Add task" at the bottom of a column (or ⌘N for To Do). **Enter** adds and stays open; **⇧Enter** adds and opens the editor; **Esc** closes. |
| Quick syntax | `!high` `!med` `!low` · `#Category` · `due:fri`, `due:14 oct`, `due:tomorrow`, `due:+3` |
| Move | Drag a card anywhere, or select it and press **⌘⌥→ / ⌘⌥←** (columns), **⌘⌥↑ / ⌘⌥↓** (order). |
| Edit | Double-click, or select and press **Space**. Changes save as you type. |
| Delete | Select and press **Delete**; an Undo toast appears for 6 s. |
| Undo | **⌘Z / ⇧⌘Z** for adds, edits, moves and deletes. |
| Find | **⌘F** filters every column; click a category chip to filter by it; **Esc** clears. |
| Archive | Done cards older than 14 days move to the Archive (toolbar ▸ archive box, or ⇧⌘A). |

## Your data

`~/Library/Group Containers/<TeamID>.com.sakshamrathi.InternshipKanban/`

- `board.json`: the board (written atomically, about 0.3 s after each change).
- `backups/`: the last 5 rolling backups (a new one at most every 10 minutes).
- A file that can't be read is never overwritten. It's renamed `board.corrupt-<time>.json`
  and the newest backup is loaded, with a banner saying so.

Settings › **Export Board as JSON…** / **Import…** (import backs up first).

## iPhone

There's an iPhone version too, with the same board, priority groups, editor and widgets,
in Apple's system colours (`scripts/generate_palette_ios.py`; the Mac keeps its own palette).
For now it keeps **its own board**: changes on the phone don't sync to the Mac.

**Install** (iOS 18 or later; free Apple ID, no App Store):

1. Connect the iPhone to this Mac with a cable, unlock it, and tap **Trust**.
2. On the iPhone, turn on **Settings › Privacy & Security › Developer Mode**. If it isn't
   listed, open Xcode › Window › Devices and Simulators once with the phone connected.
3. Run:
   ```
   scripts/install-iphone.sh
   ```
4. The first time, iOS asks you to trust the developer: **Settings › General ›
   VPN & Device Management › your Apple ID › Trust**.

Apple limits free installs to **7 days**. Run the script again to renew; your board is kept.

**Using it:** each column is a tab in the bar at the bottom, showing how many tasks it has; tap one to switch. Tap a card to edit it. Swipe a card right to
move it on (Start, Done, Resume), or left to delete it (Undo appears at the bottom).
Long-press for Move to, Priority, Move Up/Down and Duplicate. **+** (top right) adds a task and supports the
same quick syntax as the Mac (`!high`, `#Category`, `due:fri`). Archive, Settings, Undo
and Redo are under **…**.

**Widget:** long-press the Kanban Board icon (or an empty spot on the home screen ›
Edit › Add Widget) and pick small, medium or large. "→" moves a task forward without
opening the app.

## Development

```bash
xcodegen generate          # regenerate InternshipKanban.xcodeproj from project.yml
open InternshipKanban.xcodeproj
```

Signing: set `DEVELOPMENT_TEAM` in `Config/Signing.xcconfig`, or choose the team in Xcode.
The App Group is `<TeamID>.com.sakshamrathi.InternshipKanban` (Team-ID prefixed, so no
"access data from other apps" prompt on macOS 15+).

| Path | What |
|---|---|
| `Packages/KanbanCore` | Model, board rules, quick syntax, date labels, persistence, the `@Observable` store. Shared by app and widget. |
| `App/Sources` | The window: board, columns, cards, composer, editor, drag and drop, menus, settings. |
| `Widget/Sources` | WidgetKit widget (3 sizes) and the "→" App Intent. |
| `Shared` | Colours (`Palette.xcassets`, light + dark) and small views used by both. |
| `scripts` | `install.sh`, `dev-run.sh` (unsigned debug run on a scratch board), `generate_palette.py`, `make_icon.swift`. |

Tests (Swift Testing), from `Packages/KanbanCore`:

```bash
swift test
```

or **⌘U** in Xcode. Colours are generated: edit `scripts/generate_palette.py`, which also
checks every text colour against every card fill for WCAG AA.
