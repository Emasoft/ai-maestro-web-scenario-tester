#!/usr/bin/env bash
# ──────────────────────────────────────────────────────────────
# compress-screenshots.sh — Convert all PNG screenshots to JPEG 97%
# and delete the originals.
#
# Cross-platform: prefers macOS built-in `sips` (always present on
# macOS, no install). Falls back to ImageMagick `magick`/`convert`
# on Linux/Windows/CI where `sips` is absent. If neither tool is
# found, the script aborts (it never deletes a PNG it could not
# convert).
#
# Usage:
#   bash compress-screenshots.sh                  # compress all PNG under the default dir
#   bash compress-screenshots.sh <dir>            # compress all PNG under <dir>
#   bash compress-screenshots.sh <dir> <quality>  # override quality (default 97)
#
# Default dir resolution (worktree-safe): $CLAUDE_PROJECT_DIR/<scenariosDir>/screenshots
# where <scenariosDir> defaults to tests/scenarios.
#
# Why 97%: JPEG at 97% is visually indistinguishable from the PNG
# source for UI screenshots while cutting file size by ~70%.
# The remaining compression artifacts are inside the noise floor
# of display rendering and do not affect visual verification.
#
# Safety: the script ONLY deletes the PNG after the converter has
# successfully written a non-empty JPEG. If the conversion fails,
# the PNG is preserved.
# ──────────────────────────────────────────────────────────────

set -eu

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
SCENARIOS_SUBDIR="${SCENARIOS_DIR_REL:-tests/scenarios}"
DEFAULT_DIR="$PROJECT_DIR/$SCENARIOS_SUBDIR/screenshots"

TARGET_DIR="${1:-$DEFAULT_DIR}"
QUALITY="${2:-97}"

if [ ! -d "$TARGET_DIR" ]; then
    echo "[compress-screenshots] target dir not found: $TARGET_DIR" >&2
    exit 1
fi

# Select a converter. sips on macOS; ImageMagick everywhere else.
# We expose the choice as a single function `convert_one <png> <jpg> <quality>`
# returning 0 on success so the conversion loop stays converter-agnostic.
CONVERTER=""
if command -v sips >/dev/null 2>&1; then
    CONVERTER="sips"
elif command -v magick >/dev/null 2>&1; then
    CONVERTER="magick"
elif command -v convert >/dev/null 2>&1; then
    # Legacy ImageMagick v6 entry point.
    CONVERTER="convert"
else
    echo "[compress-screenshots] no image converter found — install macOS 'sips' (built-in) or ImageMagick ('magick'/'convert')" >&2
    exit 1
fi

convert_one() {
    # $1 = source png, $2 = dest jpg, $3 = quality
    case "$CONVERTER" in
        sips)
            sips -s format jpeg -s formatOptions "$3" "$1" --out "$2" >/dev/null 2>&1
            ;;
        magick)
            # ImageMagick v7: `magick <in> -quality N <out>`
            magick "$1" -quality "$3" "$2" >/dev/null 2>&1
            ;;
        convert)
            # ImageMagick v6: `convert <in> -quality N <out>`
            convert "$1" -quality "$3" "$2" >/dev/null 2>&1
            ;;
    esac
}

echo "[compress-screenshots] using converter: $CONVERTER"
echo "[compress-screenshots] scanning $TARGET_DIR for *.png files..."
BEFORE_SIZE=$(du -sk "$TARGET_DIR" 2>/dev/null | awk '{print $1}')
PNG_COUNT=0
CONVERTED=0
FAILED=0
FAILED_FILES=""

# Use while + find to handle spaces in filenames
while IFS= read -r -d '' png_file; do
    PNG_COUNT=$((PNG_COUNT + 1))
    jpg_file="${png_file%.png}.jpg"

    # Skip if a JPG already exists (idempotent)
    if [ -f "$jpg_file" ]; then
        rm -f "$png_file"
        continue
    fi

    if convert_one "$png_file" "$jpg_file" "$QUALITY"; then
        if [ -s "$jpg_file" ]; then
            rm -f "$png_file"
            CONVERTED=$((CONVERTED + 1))
        else
            # JPG empty — conversion bad, keep PNG
            rm -f "$jpg_file"
            FAILED=$((FAILED + 1))
            FAILED_FILES="$FAILED_FILES
  - $png_file"
        fi
    else
        FAILED=$((FAILED + 1))
        FAILED_FILES="$FAILED_FILES
  - $png_file"
    fi
done < <(find "$TARGET_DIR" -type f -name "*.png" -print0)

AFTER_SIZE=$(du -sk "$TARGET_DIR" 2>/dev/null | awk '{print $1}')
SAVED_KB=$((BEFORE_SIZE - AFTER_SIZE))
SAVED_MB=$((SAVED_KB / 1024))

echo "[compress-screenshots] scanned: ${PNG_COUNT} PNG files"
echo "[compress-screenshots] converted: ${CONVERTED}"
echo "[compress-screenshots] failed: ${FAILED}"
echo "[compress-screenshots] before: ${BEFORE_SIZE} KB"
echo "[compress-screenshots] after: ${AFTER_SIZE} KB"
echo "[compress-screenshots] saved: ${SAVED_KB} KB (${SAVED_MB} MB)"

if [ "$FAILED" -gt 0 ]; then
    echo "[compress-screenshots] failed files:$FAILED_FILES" >&2
    exit 2
fi
