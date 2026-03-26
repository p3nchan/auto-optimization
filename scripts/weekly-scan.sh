#!/bin/bash
# weekly-scan.sh — Tier 2: Weekly pre-scan for AI-assisted optimization
#
# Collects comprehensive workspace health data. The output is designed
# to be consumed by an AI agent that handles judgment calls:
# - Topic file content refinement
# - Daily note compression decisions
# - Project activity classification
# - Optimization suggestion review
#
# This script does NOT modify files (except browser cache cleanup).
# All destructive decisions are left to the AI or human operator.
#
# Exit codes:
#   0 = Scan completed
#   1 = Execution error
#
# Usage:
#   bash scripts/weekly-scan.sh

set -euo pipefail

# ── Source config ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.sh not found at $CONFIG_FILE" >&2
  exit 1
fi
source "$CONFIG_FILE"

TODAY=$(date +%Y-%m-%d)
FOURTEEN_DAYS_AGO=$(date_ago "$THRESHOLD_COMPRESS_DAYS")
SEVEN_DAYS_AGO=$(date_ago "$THRESHOLD_MEDIA_DAYS")
THIRTY_DAYS_AGO=$(date_ago 30)

WARNINGS=()

echo "=== WEEKLY SCAN REPORT ==="
echo "date: $TODAY"
echo "platform: $PLATFORM"
echo ""

# ============================================================
# 1. Topic Files Health
# ============================================================

echo "--- Topics Health ---"
TOPIC_COUNT=0
TOPIC_OVERSIZED=0

if [ -d "$TOPICS_DIR" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    TOPIC_COUNT=$((TOPIC_COUNT + 1))
    FNAME=$(basename "$f")
    FSIZE=$(file_size_bytes "$f")
    FSIZE_KB=$((FSIZE / 1024))

    # Check kebab-case naming
    NAMING_OK="ok"
    if ! echo "$FNAME" | grep -qE '^[a-z0-9]+(-[a-z0-9]+)*\.md$'; then
      NAMING_OK="[WARN] non-kebab"
      WARNINGS+=("topic naming: $FNAME")
    fi

    # Check size limits
    SIZE_STATUS="ok"
    if [ "$FSIZE" -gt "$LIMIT_TOPIC_SIZE_BYTES" ]; then
      SIZE_STATUS="[WARN] >${FSIZE_KB}KB (limit $(( LIMIT_TOPIC_SIZE_BYTES / 1024 ))KB)"
      TOPIC_OVERSIZED=$((TOPIC_OVERSIZED + 1))
      WARNINGS+=("topic oversized: $FNAME (${FSIZE_KB}KB)")
    elif [ "$FSIZE" -gt 1024 ]; then
      SIZE_STATUS="~${FSIZE_KB}KB (near limit)"
    fi

    echo "  $FNAME: ${FSIZE}B $SIZE_STATUS $NAMING_OK"
  done < <(find "$TOPICS_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)
fi

echo "  total: $TOPIC_COUNT files"
if [ "$TOPIC_COUNT" -gt "$LIMIT_TOPIC_FILES" ]; then
  WARNINGS+=("topic_count=$TOPIC_COUNT (>$LIMIT_TOPIC_FILES)")
  echo "  [WARN] exceeds ${LIMIT_TOPIC_FILES}-file limit"
fi
echo ""

# ============================================================
# 2. Memory Index Health
# ============================================================

echo "--- Memory Index ---"
if [ -f "$MEMORY_DIR/MEMORY.md" ]; then
  MEM_INDEX_SIZE=$(file_size_bytes "$MEMORY_DIR/MEMORY.md")
  echo "  MEMORY.md size: ${MEM_INDEX_SIZE}B"
  if [ "$MEM_INDEX_SIZE" -gt 600 ]; then
    WARNINGS+=("MEMORY.md oversized: ${MEM_INDEX_SIZE}B (>600B)")
    echo "  [WARN] exceeds 600B limit"
  fi
elif [ -f "$WS/MEMORY.md" ]; then
  MEM_INDEX_SIZE=$(file_size_bytes "$WS/MEMORY.md")
  echo "  MEMORY.md size: ${MEM_INDEX_SIZE}B (in workspace root)"
else
  echo "  MEMORY.md not found (optional)"
fi
echo ""

# ============================================================
# 3. Daily Notes Compression Candidates
# ============================================================

echo "--- Daily Notes Compression Candidates ---"
COMPRESS_COUNT=0
COMPRESS_TOTAL_KB=0

if [ -d "$MEMORY_DIR" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    FNAME=$(basename "$f")
    FSIZE=$(file_size_bytes "$f")
    FSIZE_KB=$((FSIZE / 1024))

    # Skip already compressed files (contain a marker)
    if grep -q "compressed\|Compressed\|COMPRESSED" "$f" 2>/dev/null; then
      continue
    fi

    COMPRESS_COUNT=$((COMPRESS_COUNT + 1))
    COMPRESS_TOTAL_KB=$((COMPRESS_TOTAL_KB + FSIZE_KB))
    echo "  $FNAME: ${FSIZE_KB}KB"
  done < <(find "$MEMORY_DIR" -maxdepth 1 \
    \( -name "????-??-??.md" -o -name "????-??-??-*.md" \) \
    -not -newermt "$FOURTEEN_DAYS_AGO" -type f 2>/dev/null | sort)
fi

echo "  candidates: $COMPRESS_COUNT files (~${COMPRESS_TOTAL_KB}KB total)"
echo ""

# ============================================================
# 4. Archive Status
# ============================================================

echo "--- Archive ---"
if [ -d "$ARCHIVE_DIR" ]; then
  ARCHIVE_SIZE=$(du -sk "$ARCHIVE_DIR" 2>/dev/null | cut -f1 || echo 0)
  ARCHIVE_MB=$((ARCHIVE_SIZE / 1024))
  echo "  total: ${ARCHIVE_MB}MB"

  while IFS= read -r d; do
    [ -z "$d" ] && continue
    DNAME=$(basename "$d")
    DSIZE=$(du -sk "$d" 2>/dev/null | cut -f1 || echo 0)
    DCOUNT=$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  $DNAME: ${DSIZE}KB ($DCOUNT files)"
  done < <(find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

  ARCHIVE_NEW=$(find "$ARCHIVE_DIR" -type f -newermt "$SEVEN_DAYS_AGO" 2>/dev/null | wc -l | tr -d ' ')
  echo "  new_this_week: $ARCHIVE_NEW files"
else
  echo "  (archive directory not found)"
fi
echo ""

# ============================================================
# 5. Projects Health
# ============================================================

echo "--- Projects ---"
if [ -d "$PROJECTS_DIR" ]; then
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    PNAME=$(basename "$d")

    HAS_CONTEXT="yes"
    HAS_STATUS="yes"
    CONTEXT_SIZE=""
    STATUS_SIZE=""
    ACTIVITY=""

    if [ ! -f "$d/context.md" ]; then
      HAS_CONTEXT="MISSING"
      WARNINGS+=("project missing context.md: $PNAME")
    else
      CS=$(file_size_bytes "$d/context.md")
      CONTEXT_SIZE="${CS}B"
      if [ "$CS" -gt 1024 ]; then
        CONTEXT_SIZE="[WARN] ${CS}B (>1KB)"
        WARNINGS+=("project context.md oversized: $PNAME (${CS}B)")
      fi
    fi

    if [ ! -f "$d/status.md" ]; then
      HAS_STATUS="MISSING"
      WARNINGS+=("project missing status.md: $PNAME")
    else
      SS=$(file_size_bytes "$d/status.md")
      STATUS_SIZE="${SS}B"
    fi

    # Activity detection based on most recent file modification
    LATEST_MOD=$(find "$d" -type f -name "*.md" 2>/dev/null \
      | while read -r mf; do file_mtime_epoch "$mf"; done \
      | sort -rn | head -1)
    if [ -n "$LATEST_MOD" ] && [ "$LATEST_MOD" != "0" ]; then
      NOW_EPOCH=$(date +%s)
      AGE_DAYS=$(( (NOW_EPOCH - LATEST_MOD) / 86400 ))
      if [ "$AGE_DAYS" -le 7 ]; then
        ACTIVITY="active"
      elif [ "$AGE_DAYS" -le 14 ]; then
        ACTIVITY="recent"
      elif [ "$AGE_DAYS" -le 30 ]; then
        ACTIVITY="silent(${AGE_DAYS}d)"
      else
        ACTIVITY="[WARN] stale(${AGE_DAYS}d)"
        WARNINGS+=("project stale: $PNAME (${AGE_DAYS}d)")
      fi
    fi

    echo "  $PNAME: ctx=$HAS_CONTEXT($CONTEXT_SIZE) sts=$HAS_STATUS($STATUS_SIZE) $ACTIVITY"
  done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
fi
echo ""

# ============================================================
# 6. System Health
# ============================================================

echo "--- System Health ---"

# Non-standard directories in memory/
if [ -d "$MEMORY_DIR" ]; then
  ALLOWED_DIRS="topics archive state episodic"
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    DNAME=$(basename "$d")
    if ! echo "$ALLOWED_DIRS" | grep -qw "$DNAME"; then
      echo "  [WARN] non-standard memory dir: $DNAME"
      WARNINGS+=("non-standard memory dir: $DNAME")
    fi
  done < <(find "$MEMORY_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null)
fi
echo ""

# ============================================================
# 7. Space Usage
# ============================================================

echo "--- Space Usage ---"

TOTAL_SIZE=$(du -sk "$WS" 2>/dev/null | cut -f1 || echo 0)
TOTAL_MB=$((TOTAL_SIZE / 1024))
echo "  total: ${TOTAL_MB}MB"

# Large files
if [ -f "$MEMORY_DIR/main.sqlite" ]; then
  SQLITE_BYTES=$(file_size_bytes "$MEMORY_DIR/main.sqlite")
  SQLITE_MB=$((SQLITE_BYTES / 1048576))
  echo "  embeddings_db: ${SQLITE_MB}MB"
fi

# Media subdirectories
if [ -d "$MEDIA_DIR" ]; then
  echo "  media:"
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    DNAME=$(basename "$d")
    DKB=$(du -sk "$d" 2>/dev/null | cut -f1 || echo 0)
    DMB=$((DKB / 1024))
    echo "    $DNAME: ${DMB}MB"
    if [ "$DMB" -gt "$LIMIT_MEDIA_SUBDIR_MB" ]; then
      WARNINGS+=("media/$DNAME=${DMB}MB (>${LIMIT_MEDIA_SUBDIR_MB}MB)")
    fi
  done < <(find "$MEDIA_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
fi
echo ""

# ============================================================
# 8. Environment Check
# ============================================================

echo "--- Environment ---"
NODE_PATH=$(which node 2>/dev/null || echo "not found")
NODE_VER=$(node -v 2>/dev/null || echo "N/A")
echo "  node: $NODE_VER ($NODE_PATH)"
if [ "$NODE_PATH" = "not found" ]; then
  WARNINGS+=("node not found")
fi

PYTHON_PATH=$(which python3 2>/dev/null || echo "not found")
PYTHON_VER=$(python3 --version 2>/dev/null || echo "N/A")
echo "  python: $PYTHON_VER ($PYTHON_PATH)"
echo ""

# ============================================================
# 9. Cron Health (optional)
# ============================================================

echo "--- Cron Health ---"
if [ "$CHECK_CRON_JOBS" = "true" ] && [ -f "$CRON_JOBS_FILE" ]; then
  python3 -c "
import json, time, sys
try:
    d = json.load(open('$CRON_JOBS_FILE'))
    jobs = d.get('jobs', d if isinstance(d, list) else [])
    enabled = sum(1 for j in jobs if j.get('enabled', True))
    disabled = sum(1 for j in jobs if not j.get('enabled', True))
    errored = sum(1 for j in jobs if j.get('state',{}).get('consecutiveErrors',0) > 0)
    print(f'  total: {len(jobs)} | enabled: {enabled} | disabled: {disabled} | errored: {errored}')
    disabled_jobs = [j for j in jobs if not j.get('enabled', True)]
    if disabled_jobs:
        print('  disabled_jobs:')
        now = time.time() * 1000
        for j in disabled_jobs:
            name = j.get('name', '?')
            last_run = j.get('state',{}).get('lastRunAtMs', 0)
            if last_run:
                age_days = int((now - last_run) / 86400000)
                print(f'    {name}: last_run={age_days}d ago')
            else:
                print(f'    {name}: never_ran')
except Exception as e:
    print(f'  error parsing jobs.json: {e}', file=sys.stderr)
" 2>/dev/null
else
  echo "  (cron monitoring disabled or jobs.json not found)"
fi
echo ""

# ============================================================
# SUMMARY
# ============================================================

echo "--- Summary ---"
echo "  warnings: ${#WARNINGS[@]}"
echo "  compression_candidates: $COMPRESS_COUNT files (~${COMPRESS_TOTAL_KB}KB)"
echo ""

if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo "--- All Warnings ---"
  for w in "${WARNINGS[@]}"; do
    echo "  [WARN] $w"
  done
  echo ""
fi

echo "--- AI Tasks Remaining ---"
echo "  1. Topic files content refinement (stable facts from daily notes -> topics)"
echo "  2. Daily note compression ($COMPRESS_COUNT files >$THRESHOLD_COMPRESS_DAYS days)"
echo "  3. Project health judgment (active vs stale vs archive-worthy)"
echo "  4. Optimization suggestions review"
echo "  5. Catalog rebuild (if applicable)"
echo "  6. Weekly summary generation"
echo ""

# NOTE: This script does NOT write the weekly sentinel.
# The AI session writes it after completing all judgment tasks.

echo "=== END ==="
