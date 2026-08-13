#!/bin/sh
# Sync the canonical Citizen DJ assets into the CitizenDJ Swift package's bundled resources.
#
# MVP scope is the Roland TR-808 only, so just the 27 TR-808 one-shot mp3s are copied
# (not all 8 drum machines / 212 samples), plus the two drum-data JSONs the engine reads.
#
# Run from anywhere — paths resolve relative to the repo root (the parent of this script).
# Re-run any time the canonical web-app assets change to keep the package copy in sync.
set -e

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_AUDIO="$REPO_ROOT/audio/drum_machines"
SRC_DATA="$REPO_ROOT/data"
DEST="$REPO_ROOT/Sources/CitizenDJ/Resources"
DEST_AUDIO="$DEST/audio"
DEST_DATA="$DEST/data"

rm -rf "$DEST_AUDIO" "$DEST_DATA"
mkdir -p "$DEST_AUDIO" "$DEST_DATA"

# Roland TR-808 one-shots only.
cp "$SRC_AUDIO"/Roland_Tr-808_full__*.mp3 "$DEST_AUDIO"/
# Drum-machine + pattern manifests (full JSON; engine filters to the t808 machine at runtime).
cp "$SRC_DATA/drum_machines.json" "$SRC_DATA/drum_patterns.json" "$DEST_DATA"/

# Phrase loop sets — longer melodic loops layered over the drums. Copied recursively;
# .DS_Store stripped. The dir + a .keep are always created so the package builds even with
# no phrases present (the feature then degrades to drums-only).
DEST_PHRASES="$DEST/phrases"
SRC_PHRASES="$REPO_ROOT/audio/phrases"
rm -rf "$DEST_PHRASES"
mkdir -p "$DEST_PHRASES"
if [ -d "$SRC_PHRASES" ]; then
  cp -R "$SRC_PHRASES"/. "$DEST_PHRASES"/
  find "$DEST_PHRASES" -name '.DS_Store' -delete
fi
touch "$DEST_PHRASES/.keep"

# Drum kits — custom percussion packs, one directory per kit. Recursive; .DS_Store stripped.
DEST_KITS="$DEST/drumkits"
SRC_KITS="$REPO_ROOT/audio/drumkits"
rm -rf "$DEST_KITS"
mkdir -p "$DEST_KITS"
if [ -d "$SRC_KITS" ]; then
  cp -R "$SRC_KITS"/. "$DEST_KITS"/
  find "$DEST_KITS" -name '.DS_Store' -delete
fi
touch "$DEST_KITS/.keep"

AUDIO_COUNT=$(ls "$DEST_AUDIO" | wc -l | tr -d ' ')
DATA_COUNT=$(ls "$DEST_DATA" | wc -l | tr -d ' ')
PHRASE_COUNT=$(find "$DEST_PHRASES" -type f ! -name '.keep' 2>/dev/null | wc -l | tr -d ' ')
KIT_COUNT=$(find "$DEST_KITS" -type f ! -name '.keep' 2>/dev/null | wc -l | tr -d ' ')
echo "Synced CitizenDJ resources:"
echo "  $AUDIO_COUNT TR-808 mp3s   -> Sources/CitizenDJ/Resources/audio/"
echo "  $DATA_COUNT json files    -> Sources/CitizenDJ/Resources/data/"
echo "  $PHRASE_COUNT phrase loops -> Sources/CitizenDJ/Resources/phrases/"
echo "  $KIT_COUNT kit samples     -> Sources/CitizenDJ/Resources/drumkits/"
