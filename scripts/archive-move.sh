#!/bin/bash
# archive-move.sh — Helper: Move memory daily notes to archive
#
# Automatically determines the correct archive subdirectory based on
# the date in the filename (early/late split at day 15).
#
# Usage:
#   bash scripts/archive-move.sh /path/to/memory/2025-03-05.md
#   bash scripts/archive-move.sh /path/to/memory/2025-03-05-meeting-notes.md

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.sh not found at $CONFIG_FILE" >&2
  exit 1
fi
source "$CONFIG_FILE"

# ── Argument check ───────────────────────────────────────────
if [ $# -ne 1 ]; then
  echo "Usage: bash archive-move.sh /path/to/memory/YYYY-MM-DD.md" >&2
  echo "       bash archive-move.sh /path/to/memory/YYYY-MM-DD-suffix.md" >&2
  exit 1
fi

SRC="$1"

if [ ! -f "$SRC" ]; then
  echo "Error: file not found: $SRC" >&2
  exit 1
fi

# ── Extract date from filename ───────────────────────────────
BASENAME=$(basename "$SRC")
DATE_PART=$(echo "$BASENAME" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)

if [ -z "$DATE_PART" ]; then
  echo "Error: cannot extract date from filename (expected YYYY-MM-DD): $BASENAME" >&2
  exit 1
fi

YEAR=$(echo "$DATE_PART" | cut -d'-' -f1)
MONTH=$(echo "$DATE_PART" | cut -d'-' -f2)
DAY=$(echo "$DATE_PART" | cut -d'-' -f3)

# ── Determine early/late ─────────────────────────────────────
DAY_NUM=$((10#$DAY))  # Force decimal (avoid 08/09 octal issues)

if [ "$DAY_NUM" -le 15 ]; then
  PERIOD="early"
else
  PERIOD="late"
fi

TARGET_DIR="$ARCHIVE_DIR/${YEAR}-${MONTH}-${PERIOD}"

# ── Determine destination filename ───────────────────────────
# If the original already has -full suffix, keep it.
# Otherwise, rename to YYYY-MM-DD-full.md
if echo "$BASENAME" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}-full\.md$'; then
  DEST_NAME="$BASENAME"
else
  DEST_NAME="${DATE_PART}-full.md"
fi

DEST="$TARGET_DIR/$DEST_NAME"

# ── Execute move ─────────────────────────────────────────────
mkdir -p "$TARGET_DIR"

if [ -f "$DEST" ]; then
  echo "Warning: destination already exists, will overwrite: $DEST" >&2
fi

mv "$SRC" "$DEST"
echo "${SRC} -> ${DEST}"
