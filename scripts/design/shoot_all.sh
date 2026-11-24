#!/bin/zsh
# Screenshots of every app state, light and dark, into design-handoff/app.
cd "$(dirname "$0")/../.."
OUT=design-handoff/app; mkdir -p $OUT
S=scripts/design/shoot.sh
for LOOK in light dark; do
  $S $OUT/01-board-$LOOK.png               full    $LOOK ""
  $S $OUT/02-board-first-launch-$LOOK.png  seed    $LOOK ""
  $S $OUT/03-board-empty-$LOOK.png         empty   $LOOK ""
  $S $OUT/04-card-selected-$LOOK.png       full    $LOOK "select:Mock interview"
  $S $OUT/05-composer-open-$LOOK.png       full    $LOOK "composer:inProgress"
  $S $OUT/06-editor-$LOOK.png              full    $LOOK "editor:Mock interview"
  $S $OUT/07-editor-on-hold-card-$LOOK.png full    $LOOK "editor:Brochure sign-off"
  $S $OUT/08-search-$LOOK.png              full    $LOOK "search:brochure"
  $S $OUT/09-category-filter-$LOOK.png     full    $LOOK "category:Prep"
  $S $OUT/10-delete-toast-$LOOK.png        full    $LOOK "toast:Shortlist 20"
  $S $OUT/11-archive-$LOOK.png             full    $LOOK "archive"
  $S $OUT/12-archive-empty-$LOOK.png       seed    $LOOK "archive"
  $S $OUT/13-settings-$LOOK.png            full    $LOOK "settings" "" "Kanban Board Settings"
  $S $OUT/14-restored-from-backup-$LOOK.png corrupt $LOOK ""
  $S $OUT/15-read-only-newer-file-$LOOK.png newer  $LOOK ""
  $S $OUT/16-narrow-window-$LOOK.png       full    $LOOK "" 720x640
  $S $OUT/17-wide-window-$LOOK.png         full    $LOOK "" 1600x900
done
