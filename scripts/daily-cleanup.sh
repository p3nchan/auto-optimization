#!/bin/bash
# daily-cleanup.sh — Tier 1: Daily deterministic cleanup
#
# Performs rule-based cleanup of temporary files, old media, stale logs,
# and excess backups. Outputs structured results for optional AI post-processing.
#
# Exit codes:
#   0 = Completed (may or may not have cleaned anything)
#   1 = Execution error
#
# Usage:
#   bash scripts/daily-cleanup.sh
#
# Dependencies: bash 4+, standard unix tools
# Optional: trash (macOS), jq

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
THREE_DAYS_AGO=$(date_ago "$THRESHOLD_TEMP_DAYS")
SEVEN_DAYS_AGO=$(date_ago "$THRESHOLD_MEDIA_DAYS")
FOURTEEN_DAYS_AGO=$(date_ago "$THRESHOLD_CRON_LOG_DAYS")

# Counters
ACTIONS=0
WARNINGS=()

# ── Helper: safe delete ──────────────────────────────────────
safe_delete() {
  if [ "$USE_TRASH" = "true" ] && command -v trash &>/dev/null; then
    trash "$1" 2>/dev/null && return 0
  fi
  rm -f "$1" 2>/dev/null
}

# Pipe-friendly: reads null-delimited paths from stdin, deletes each
delete_find_results() {
  local delete_mode="$1"  # "trash" or "rm"
  local count=0
  local file

  while IFS= read -r -d "" file; do
    [ -z "$file" ] && continue
    if [ "$delete_mode" = "rm" ]; then
      rm -f "$file" 2>/dev/null && count=$((count + 1))
    else
      safe_delete "$file" && count=$((count + 1))
    fi
  done

  echo "$count"
}

# ============================================================
# PHASE 1: Early Exit Check
# ============================================================
# Quick scan to see if any cleanup is needed at all.
# If the workspace is already clean, skip to health checks.

SCATTERED=0
if [ -d "$MEMORY_DIR" ]; then
  SCATTERED=$(find "$MEMORY_DIR" -maxdepth 1 -name "????-??-??-*.md" \
    -not -newermt "$THREE_DAYS_AGO" 2>/dev/null | wc -l | tr -d ' ')
fi

MEDIA_OLD=0
if [ -d "$MEDIA_DIR/inbound" ]; then
  MEDIA_OLD=$(find "$MEDIA_DIR/inbound" -type f \
    -not -newermt "$SEVEN_DAYS_AGO" 2>/dev/null | wc -l | tr -d ' ')
fi

CRON_OLD=0
if [ -d "$CRON_DIR/runs" ]; then
  CRON_OLD=$(find "$CRON_DIR/runs" -name "*.jsonl" \
    -not -newermt "$FOURTEEN_DAYS_AGO" 2>/dev/null | wc -l | tr -d ' ')
fi

TEMP_OLD=$(find "$WS" -maxdepth 1 \
  \( -name "*.bak" -o -name "screen0_*.png" -o -name "temp_*.txt" \
     -o -name "*.tmp" -o -name "*.swp" \) \
  -not -newermt "$THREE_DAYS_AGO" 2>/dev/null | wc -l | tr -d ' ')

NEEDS_CLEANUP=false
if [ "$SCATTERED" -gt 0 ] || [ "$MEDIA_OLD" -gt 0 ] || \
   [ "$CRON_OLD" -gt 0 ] || [ "$TEMP_OLD" -gt 0 ]; then
  NEEDS_CLEANUP=true
fi

# ============================================================
# PHASE 2: Health Checks (always run)
# ============================================================

# Database size check
SQLITE_MB=0
for DB_PATH in "$MEMORY_DIR/main.sqlite" "$WS/main.sqlite" "$WS/workspace.db"; do
  if [ -f "$DB_PATH" ]; then
    DB_BYTES=$(file_size_bytes "$DB_PATH")
    DB_MB=$(( DB_BYTES / 1048576 ))
    if [ "$DB_MB" -gt "$SQLITE_MB" ]; then
      SQLITE_MB=$DB_MB
    fi
  fi
done
if [ "$SQLITE_MB" -gt "$LIMIT_EMBEDDINGS_MB" ]; then
  WARNINGS+=("db_size=${SQLITE_MB}MB (>${LIMIT_EMBEDDINGS_MB}MB)")
fi

# Optional gateway check
GATEWAY_STATUS="skipped"
if [ "$CHECK_GATEWAY" = "true" ]; then
  if curl -sf --max-time 5 "$GATEWAY_URL" > /dev/null 2>&1; then
    GATEWAY_STATUS="ok"
  else
    GATEWAY_STATUS="down"
    WARNINGS+=("gateway=down")
  fi
fi

# Memory file count
MD_COUNT=0
if [ -d "$MEMORY_DIR" ]; then
  MD_COUNT=$(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$MD_COUNT" -gt "$LIMIT_MEMORY_MD_FILES" ]; then
    WARNINGS+=("memory_md_count=${MD_COUNT} (>${LIMIT_MEMORY_MD_FILES})")
  fi
fi

# Naming compliance check (memory files should be YYYY-MM-DD.md or YYYY-MM-DD-*.md)
NON_COMPLIANT_FILES=""
if [ -d "$MEMORY_DIR" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    bname=$(basename "$f")
    NON_COMPLIANT_FILES="${NON_COMPLIANT_FILES}${bname}\n"
  done < <(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" \
    ! -name "????-??-??.md" \
    ! -name "????-??-??-*.md" \
    ! -name "MEMORY.md" \
    ! -name "README.md" \
    -type f 2>/dev/null)

  if [ -n "$NON_COMPLIANT_FILES" ]; then
    WARNINGS+=("non_compliant_memory_files")
  fi
fi

# ============================================================
# PHASE 2.5: Early Exit Decision
# ============================================================

if ! $NEEDS_CLEANUP; then
  # Write sentinel
  mkdir -p "$(dirname "$SENTINEL_DAILY")"
  echo "$(date +%Y-%m-%dT%H:%M:%S)" > "$SENTINEL_DAILY"

  if [ ${#WARNINGS[@]} -eq 0 ]; then
    # Level 2: completely clean
    echo "=== DAILY CLEANUP REPORT ==="
    echo "date: $TODAY"
    echo "early_exit: L2"
    echo "actions: 0"
    echo "health: all_ok"
    echo "sqlite_mb: $SQLITE_MB"
    echo "md_count: $MD_COUNT"
    echo "=== END ==="
    exit 0
  else
    # Level 1: no cleanup needed but has warnings
    echo "=== DAILY CLEANUP REPORT ==="
    echo "date: $TODAY"
    echo "early_exit: L1"
    echo "actions: 0"
    echo "warnings:"
    for w in "${WARNINGS[@]}"; do
      echo "  - $w"
    done
    echo "sqlite_mb: $SQLITE_MB"
    echo "md_count: $MD_COUNT"
    echo "gateway: $GATEWAY_STATUS"
    echo "=== END ==="
    exit 0
  fi
fi

# ============================================================
# PHASE 3: Cleanup Operations
# ============================================================

# --- 3a: Root temp files ---

# .bak files: keep newest N, delete the rest
BAK_DELETED=0
BAK_FILES=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  BAK_FILES+=("$f")
done < <(find "$WS" -maxdepth 1 -name "*.bak" -type f -print0 2>/dev/null \
  | sort -z -r | tr '\0' '\n')
BAK_COUNT=${#BAK_FILES[@]}
if [ "$BAK_COUNT" -gt "$LIMIT_BAK_KEEP" ]; then
  for f in "${BAK_FILES[@]:$LIMIT_BAK_KEEP}"; do
    safe_delete "$f"
    BAK_DELETED=$((BAK_DELETED + 1))
  done
  ACTIONS=$((ACTIONS + BAK_DELETED))
fi

# Screenshots older than threshold
SCREEN_DELETED=0
SCREEN_DELETED=$(find "$WS" -maxdepth 1 -name "screen0_*.png" \
  -not -newermt "$THREE_DAYS_AGO" -print0 2>/dev/null \
  | delete_find_results trash)
ACTIONS=$((ACTIONS + SCREEN_DELETED))

# Temp/swap files older than threshold
TEMP_DELETED=0
TEMP_DELETED=$(find "$WS" -maxdepth 1 \
  \( -name "temp_*.txt" -o -name "*.tmp" -o -name "*.swp" \) \
  -not -newermt "$THREE_DAYS_AGO" -print0 2>/dev/null \
  | delete_find_results trash)
ACTIONS=$((ACTIONS + TEMP_DELETED))

# --- 3b: media/inbound older than threshold ---
MEDIA_DELETED=0
MEDIA_FREED_KB=0
if [ -d "$MEDIA_DIR/inbound" ]; then
  MEDIA_SIZE_BEFORE=$(du -sk "$MEDIA_DIR/inbound" 2>/dev/null | cut -f1 || echo 0)

  MEDIA_DELETED=$(find "$MEDIA_DIR/inbound" -type f \
    -not -newermt "$SEVEN_DAYS_AGO" -print0 2>/dev/null \
    | delete_find_results trash)

  MEDIA_SIZE_AFTER=$(du -sk "$MEDIA_DIR/inbound" 2>/dev/null | cut -f1 || echo 0)
  MEDIA_FREED_KB=$((MEDIA_SIZE_BEFORE - MEDIA_SIZE_AFTER))
  ACTIONS=$((ACTIONS + MEDIA_DELETED))
fi

# --- 3c: Empty date directories in media ---
MEDIA_EMPTY_DIRS_DELETED=0
if [ -d "$MEDIA_DIR" ]; then
  while IFS= read -r d; do
    [ -z "$d" ] && continue
    DNAME=$(basename "$d")
    # Only remove date-named empty directories (YYYY-MM-DD)
    if echo "$DNAME" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
      rmdir "$d" 2>/dev/null && MEDIA_EMPTY_DIRS_DELETED=$((MEDIA_EMPTY_DIRS_DELETED + 1))
    fi
  done < <(find "$MEDIA_DIR" -mindepth 2 -maxdepth 2 -type d -empty 2>/dev/null)
  ACTIONS=$((ACTIONS + MEDIA_EMPTY_DIRS_DELETED))
fi

# --- 3d: cron/runs logs older than threshold ---
CRON_DELETED=0
if [ -d "$CRON_DIR/runs" ]; then
  CRON_DELETED=$(find "$CRON_DIR/runs" -name "*.jsonl" \
    -not -newermt "$FOURTEEN_DAYS_AGO" -print0 2>/dev/null \
    | delete_find_results rm)
  ACTIONS=$((ACTIONS + CRON_DELETED))
fi

# Cron backup files: keep newest N
CRON_BAK_DELETED=0
CRON_BAKS=()
while IFS= read -r f; do
  [ -z "$f" ] && continue
  CRON_BAKS+=("$f")
done < <(find "$CRON_DIR" -maxdepth 1 -name "jobs.json.bak.*" -type f -print0 2>/dev/null \
  | sort -z -r | tr '\0' '\n')
CRON_BAK_COUNT=${#CRON_BAKS[@]}
if [ "$CRON_BAK_COUNT" -gt "$LIMIT_CRON_BAK_KEEP" ]; then
  for f in "${CRON_BAKS[@]:$LIMIT_CRON_BAK_KEEP}"; do
    rm -f "$f"
    CRON_BAK_DELETED=$((CRON_BAK_DELETED + 1))
  done
  ACTIONS=$((ACTIONS + CRON_BAK_DELETED))
fi

# ============================================================
# PHASE 4: Collect data for AI assessment
# ============================================================
# Scattered memory files that need human/AI judgment
# (is the content complete or still in-progress?)

SCATTERED_LIST=""
if [ -d "$MEMORY_DIR" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    SCATTERED_LIST="${SCATTERED_LIST}$(basename "$f")\n"
  done < <(find "$MEMORY_DIR" -maxdepth 1 -name "????-??-??-*.md" \
    -not -newermt "$THREE_DAYS_AGO" 2>/dev/null | sort)
fi

# ============================================================
# PHASE 5: Write sentinel + Output report
# ============================================================

mkdir -p "$(dirname "$SENTINEL_DAILY")"
echo "$(date +%Y-%m-%dT%H:%M:%S)" > "$SENTINEL_DAILY"

echo "=== DAILY CLEANUP REPORT ==="
echo "date: $TODAY"
echo "early_exit: none"
echo "actions: $ACTIONS"
echo ""
echo "--- Cleanup Results ---"
echo "bak_deleted: $BAK_DELETED"
echo "screenshots_deleted: $SCREEN_DELETED"
echo "temp_deleted: $TEMP_DELETED"
echo "media_deleted: $MEDIA_DELETED (freed ${MEDIA_FREED_KB}KB)"
echo "media_empty_dirs_deleted: $MEDIA_EMPTY_DIRS_DELETED"
echo "cron_logs_deleted: $CRON_DELETED"
echo "cron_bak_deleted: $CRON_BAK_DELETED"
echo ""
echo "--- Health ---"
echo "gateway: $GATEWAY_STATUS"
echo "sqlite_mb: $SQLITE_MB"
echo "md_count: $MD_COUNT"
echo ""

if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo "--- Warnings ---"
  for w in "${WARNINGS[@]}"; do
    echo "  [WARN] $w"
  done
  echo ""
fi

if [ -n "$SCATTERED_LIST" ]; then
  echo "--- AI Assessment Needed ---"
  echo "Scattered files (>${THRESHOLD_TEMP_DAYS} days, need complete/in-progress judgment):"
  echo -e "$SCATTERED_LIST"
  echo ""
fi

if [ -n "$NON_COMPLIANT_FILES" ]; then
  echo "--- Non-compliant Filenames ---"
  echo -e "$NON_COMPLIANT_FILES"
  echo ""
fi

echo "=== END ==="
