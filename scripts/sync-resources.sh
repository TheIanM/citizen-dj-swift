#!/bin/sh
# Sync project assets into the CitizenDJ Swift package's bundled resources:
#   - data/drum_patterns.json     (the 16-step pattern library + patternKey)
#   - audio/phrases (recursive)   (melodic loop sets; bulk, gitignored)
#   - audio/drumkits (recursive)  (custom drum kits; bulk, gitignored)
#
# Run from anywhere — paths resolve relative to the repo root (parent of this script).
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DATA="$REPO_ROOT/data"
DEST="$REPO_ROOT/Sources/CitizenDJ/Resources"
DEST_DATA="$DEST/data"
DEST_PHRASES="$DEST/phrases"
DEST_KITS="$DEST/drumkits"

rm -rf "$DEST_DATA" "$DEST_PHRASES" "$DEST_KITS"
mkdir -p "$DEST_DATA" "$DEST_PHRASES" "$DEST_KITS"

# Pattern manifest (kit-agnostic: the engine reads it for patterns + the code list).
cp "$SRC_DATA/drum_patterns.json" "$DEST_DATA"/

# Phrase loop sets and drum kits, copied recursively with .DS_Store stripped. A .keep is
# always left so the dirs (and the package build) exist even with no samples present.
sync_bulk() {
    src="$1"; dst="$2"
    if [ -d "$src" ]; then
        cp -R "$src"/. "$dst"/
        find "$dst" -name '.DS_Store' -delete
    fi
    touch "$dst/.keep"
}
sync_bulk "$REPO_ROOT/audio/phrases" "$DEST_PHRASES"
sync_bulk "$REPO_ROOT/audio/drumkits" "$DEST_KITS"

DATA_COUNT=$(ls "$DEST_DATA" | wc -l | tr -d ' ')
PHRASE_COUNT=$(find "$DEST_PHRASES" -type f ! -name '.keep' 2>/dev/null | wc -l | tr -d ' ')
KIT_COUNT=$(find "$DEST_KITS" -type f ! -name '.keep' 2>/dev/null | wc -l | tr -d ' ')
echo "Synced CitizenDJ resources:"
echo "  $DATA_COUNT json file      -> Sources/CitizenDJ/Resources/data/"
echo "  $PHRASE_COUNT phrase loops -> Sources/CitizenDJ/Resources/phrases/"
echo "  $KIT_COUNT kit samples     -> Sources/CitizenDJ/Resources/drumkits/"
