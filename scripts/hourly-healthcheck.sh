#!/bin/bash
# hourly-healthcheck.sh — Tier 0: Hourly deterministic health checks
#
# Checks sentinel file freshness, log errors, resource usage, and
# deduplicates repeated warnings to avoid alert fatigue.
#
# Exit codes:
#   0 = All clear
#   1 = Warnings (report but don't auto-fix)
#   2 = Errors (escalate to AI or human)
#
# Usage:
#   bash scripts/hourly-healthcheck.sh
#
# Dependencies: bash 4+, standard unix tools
# Optional: sqlite3 (for DB size checks)

set -uo pipefail

# ── Source config ────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.sh not found at $CONFIG_FILE" >&2
  echo "Copy config/config.sh.example to config/config.sh and set WORKSPACE_ROOT" >&2
  exit 2
fi
source "$CONFIG_FILE"

ERRORS=()
WARNINGS=()
INFO=()

# ============================================================
# SECTION 1: Sentinel File Freshness
# ============================================================
# Sentinel files record when each maintenance tier last completed.
# If a sentinel is stale, that tier's job may have failed silently.

NOW=$(date +%s)

check_sentinel() {
  local name="$1"
  local filepath="$2"
  local stale_threshold="$3"  # in seconds
  local unit="$4"             # "h" or "d" for display

  if [ ! -f "$filepath" ]; then
    INFO+=("sentinel: $name not found (first run?)")
    return
  fi

  local ts
  ts=$(cat "$filepath" 2>/dev/null || echo "")
  if [ -z "$ts" ]; then
    WARNINGS+=("sentinel: $name file empty")
    return
  fi

  local epoch
  epoch=$(iso_to_epoch "$ts")
  if [ "$epoch" = "0" ]; then
    WARNINGS+=("sentinel: $name has invalid timestamp: $ts")
    return
  fi

  local age=$(( NOW - epoch ))
  local age_display

  if [ "$unit" = "h" ]; then
    age_display="$(( age / 3600 ))h"
    local limit_display="$(( stale_threshold / 3600 ))h"
  else
    age_display="$(( age / 86400 ))d"
    local limit_display="$(( stale_threshold / 86400 ))d"
  fi

  if [ "$age" -gt "$stale_threshold" ]; then
    WARNINGS+=("sentinel: $name stale (${age_display} old, limit ${limit_display})")
  fi
}

check_sentinel "daily"   "$SENTINEL_DAILY"   $(( SENTINEL_DAILY_STALE_HOURS * 3600 )) "h"
check_sentinel "weekly"  "$SENTINEL_WEEKLY"  $(( SENTINEL_WEEKLY_STALE_DAYS * 86400 )) "d"
check_sentinel "monthly" "$SENTINEL_MONTHLY" $(( SENTINEL_MONTHLY_STALE_DAYS * 86400 )) "d"

# ============================================================
# SECTION 2: Log Review (past 60 minutes)
# ============================================================

# Count error-level entries in recent logs
GW_ERRORS=0
if [ -d "$LOGS_DIR" ]; then
  ONE_HOUR_AGO=$(date_ago 0)  # We use find -newermt instead
  GW_ERRORS=$(find "$LOGS_DIR" -name "*.log" -newermt "1 hour ago" \
    -exec grep -ci "ERROR\|FATAL\|CRASH\|UNCAUGHT" {} + 2>/dev/null \
    | awk '{s+=$0} END {print s+0}')
fi
if [ "$GW_ERRORS" -gt 0 ]; then
  WARNINGS+=("logs: ${GW_ERRORS} error(s) in last hour")
fi

# Check recent cron run failures
CRON_FAILS=0
if [ "$CHECK_CRON_JOBS" = "true" ] && [ -d "$CRON_DIR/runs" ]; then
  for run_file in $(find "$CRON_DIR/runs" -name "*.json" -newermt "1 hour ago" 2>/dev/null); do
    if grep -q '"status":"failed"' "$run_file" 2>/dev/null; then
      CRON_FAILS=$((CRON_FAILS + 1))
      FAIL_NAME=$(basename "$run_file" .json)
      WARNINGS+=("cron-fail: ${FAIL_NAME}")
    fi
  done
fi

# ============================================================
# SECTION 3: Resource Checks
# ============================================================

# Memory directory file count
MEMORY_COUNT=0
if [ -d "$MEMORY_DIR" ]; then
  MEMORY_COUNT=$(find "$MEMORY_DIR" -maxdepth 1 -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
  if [ "$MEMORY_COUNT" -gt "$LIMIT_MEMORY_MD_FILES" ]; then
    WARNINGS+=("memory-files: ${MEMORY_COUNT} (limit ${LIMIT_MEMORY_MD_FILES})")
  fi
fi

# Workspace-level SQLite DB size check
SQLITE_SIZE=0
for DB_PATH in "$WS/main.sqlite" "$WS/workspace.db"; do
  if [ -f "$DB_PATH" ]; then
    DB_BYTES=$(file_size_bytes "$DB_PATH")
    DB_MB=$(( DB_BYTES / 1048576 ))
    if [ "$DB_MB" -gt "$SQLITE_SIZE" ]; then
      SQLITE_SIZE=$DB_MB
    fi
  fi
done
if [ "$SQLITE_SIZE" -gt "$LIMIT_SQLITE_MB" ]; then
  WARNINGS+=("sqlite: ${SQLITE_SIZE}MB (limit ${LIMIT_SQLITE_MB}MB)")
fi

# Embeddings DB size (informational, large is expected)
EMBED_SIZE=0
if [ -f "$MEMORY_DIR/main.sqlite" ]; then
  EMBED_BYTES=$(file_size_bytes "$MEMORY_DIR/main.sqlite")
  EMBED_SIZE=$(( EMBED_BYTES / 1048576 ))
fi

# Optional: gateway health check
GATEWAY_STATUS="skipped"
if [ "$CHECK_GATEWAY" = "true" ]; then
  if curl -sf --max-time 5 "$GATEWAY_URL" > /dev/null 2>&1; then
    GATEWAY_STATUS="ok"
  else
    GATEWAY_STATUS="down"
    WARNINGS+=("gateway=down ($GATEWAY_URL)")
  fi
fi

# ============================================================
# SECTION 4: Error Deduplication
# ============================================================
# If the same warning pattern appears on consecutive runs, suppress
# until the 3rd occurrence to avoid alert fatigue.

DEDUP_HASH_FILE="$SENTINEL_DIR/.last-error-hash"
DEDUP_COUNT_FILE="$SENTINEL_DIR/.error-repeat-count"

if [ ${#ERRORS[@]} -gt 0 ] || [ ${#WARNINGS[@]} -gt 0 ]; then
  CURRENT_HASH=$(echo "${ERRORS[*]:-} ${WARNINGS[*]:-}" | shasum -a 256 | cut -d' ' -f1)

  if [ -f "$DEDUP_HASH_FILE" ]; then
    LAST_HASH=$(cat "$DEDUP_HASH_FILE" 2>/dev/null || echo "")
    if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
      REPEAT_COUNT=1
      if [ -f "$DEDUP_COUNT_FILE" ]; then
        REPEAT_COUNT=$(( $(cat "$DEDUP_COUNT_FILE" 2>/dev/null || echo "0") + 1 ))
      fi
      echo "$REPEAT_COUNT" > "$DEDUP_COUNT_FILE"

      if [ "$REPEAT_COUNT" -lt 3 ]; then
        INFO+=("dedup: same pattern as last check (repeat #${REPEAT_COUNT}, suppressing)")
        ERRORS=()
        WARNINGS=()
      else
        WARNINGS+=("dedup: same error pattern 3+ consecutive times, escalating")
      fi
    else
      echo "0" > "$DEDUP_COUNT_FILE"
    fi
  fi
  echo "$CURRENT_HASH" > "$DEDUP_HASH_FILE"
else
  [ -f "$DEDUP_HASH_FILE" ] && rm -f "$DEDUP_HASH_FILE"
  [ -f "$DEDUP_COUNT_FILE" ] && rm -f "$DEDUP_COUNT_FILE"
fi

# ============================================================
# SECTION 5: Output
# ============================================================

echo "=== HOURLY HEALTH CHECK ==="
echo "timestamp: $(date +%Y-%m-%dT%H:%M:%S)"
echo "platform: $PLATFORM"
echo "memory_files: ${MEMORY_COUNT}"
echo "sqlite_mb: ${SQLITE_SIZE}"
echo "embeddings_mb: ${EMBED_SIZE}"
echo "gateway: ${GATEWAY_STATUS}"
echo "log_errors: ${GW_ERRORS}"
echo "cron_fails: ${CRON_FAILS}"
echo ""

if [ ${#ERRORS[@]} -gt 0 ]; then
  echo "## ERRORS"
  for e in "${ERRORS[@]}"; do
    echo "  [ERROR] $e"
  done
  echo ""
fi

if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo "## WARNINGS"
  for w in "${WARNINGS[@]}"; do
    echo "  [WARN] $w"
  done
  echo ""
fi

if [ ${#INFO[@]} -gt 0 ]; then
  echo "## INFO"
  for i in "${INFO[@]}"; do
    echo "  [INFO] $i"
  done
  echo ""
fi

echo "=== END ==="

# Exit code determines what the orchestrator does next
if [ ${#ERRORS[@]} -gt 0 ]; then
  exit 2
elif [ ${#WARNINGS[@]} -gt 0 ]; then
  exit 1
else
  exit 0
fi
