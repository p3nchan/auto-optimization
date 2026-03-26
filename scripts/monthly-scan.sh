#!/bin/bash
# monthly-scan.sh — Tier 3: Monthly deep audit pre-scan
#
# Collects environment snapshots, deep hygiene data, and system complexity
# metrics. Designed to be consumed by an AI agent for:
# - Environment manifest diffing
# - Topic overlap detection
# - Archive capacity planning
# - System complexity governance
# - Quarterly trend analysis (on quarter months)
#
# Exit codes:
#   0 = Scan completed
#   1 = Execution error
#
# Usage:
#   bash scripts/monthly-scan.sh

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
CURRENT_MONTH=$(date +%m)
THIRTY_DAYS_AGO=$(date_ago 30)
SIXTY_DAYS_AGO=$(date_ago 60)

WARNINGS=()

echo "=== MONTHLY SCAN REPORT ==="
echo "date: $TODAY"
echo "month: $(date +%Y-%m)"
echo "platform: $PLATFORM"
echo ""

# ============================================================
# 1. Environment Snapshot
# ============================================================
# Captures installed packages for manifest diffing.
# Adapt this section to your package managers.

echo "--- Environment Snapshot ---"

# Homebrew (macOS)
if command -v brew &>/dev/null; then
  echo "  [brew formulas]"
  brew list --formula 2>/dev/null | sort | sed 's/^/    /'
  echo ""
  echo "  [brew casks]"
  brew list --cask 2>/dev/null | sort | sed 's/^/    /'
  echo ""
  echo "  [brew taps]"
  brew tap 2>/dev/null | sort | sed 's/^/    /'
  echo ""
fi

# APT (Debian/Ubuntu)
if command -v dpkg &>/dev/null && [ "$PLATFORM" = "linux" ]; then
  echo "  [apt packages (manually installed)]"
  apt-mark showmanual 2>/dev/null | sort | sed 's/^/    /'
  echo ""
fi

# npm global
if command -v npm &>/dev/null; then
  echo "  [npm global]"
  npm ls -g --depth=0 2>/dev/null | sed 's/^/    /'
  echo ""
fi

# pip global
if command -v pip3 &>/dev/null; then
  echo "  [pip3 packages]"
  pip3 list --format=columns 2>/dev/null | tail -n +3 | sed 's/^/    /'
  echo ""
fi

# Node version
echo "  [node]"
echo "    version: $(node -v 2>/dev/null || echo 'N/A')"
echo "    path: $(which node 2>/dev/null || echo 'not found')"
echo ""

# Python version
echo "  [python]"
echo "    version: $(python3 --version 2>/dev/null || echo 'N/A')"
echo "    path: $(which python3 2>/dev/null || echo 'not found')"
echo ""

# ============================================================
# 2. Topic Staleness (>30 days since last edit)
# ============================================================

echo "--- Topic Staleness ---"
STALE_TOPICS=0
if [ -d "$TOPICS_DIR" ]; then
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    FNAME=$(basename "$f")
    MTIME=$(file_mtime_epoch "$f")
    NOW_EPOCH=$(date +%s)
    AGE_DAYS=$(( (NOW_EPOCH - MTIME) / 86400 ))
    if [ "$AGE_DAYS" -gt 30 ]; then
      STALE_TOPICS=$((STALE_TOPICS + 1))
      echo "  [WARN] $FNAME: ${AGE_DAYS}d since last modified"
      WARNINGS+=("stale topic: $FNAME (${AGE_DAYS}d)")
    else
      echo "  [OK] $FNAME: ${AGE_DAYS}d"
    fi
  done < <(find "$TOPICS_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)
fi
echo "  stale_count: $STALE_TOPICS"
echo ""

# ============================================================
# 3. Archive Capacity Audit
# ============================================================

echo "--- Archive Capacity ---"
if [ -d "$ARCHIVE_DIR" ]; then
  ARCHIVE_TOTAL_KB=$(du -sk "$ARCHIVE_DIR" 2>/dev/null | cut -f1 || echo 0)
  ARCHIVE_TOTAL_MB=$((ARCHIVE_TOTAL_KB / 1024))
  echo "  total: ${ARCHIVE_TOTAL_MB}MB"
  if [ "$ARCHIVE_TOTAL_MB" -gt "$LIMIT_ARCHIVE_MB" ]; then
    WARNINGS+=("archive=${ARCHIVE_TOTAL_MB}MB (>${LIMIT_ARCHIVE_MB}MB)")
    echo "  [WARN] exceeds ${LIMIT_ARCHIVE_MB}MB limit"
  fi

  while IFS= read -r d; do
    [ -z "$d" ] && continue
    DNAME=$(basename "$d")
    DKB=$(du -sk "$d" 2>/dev/null | cut -f1 || echo 0)
    DCOUNT=$(find "$d" -type f 2>/dev/null | wc -l | tr -d ' ')
    echo "  $DNAME: ${DKB}KB ($DCOUNT files)"
  done < <(find "$ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
else
  echo "  (archive directory not found)"
fi
echo ""

# ============================================================
# 4. System Complexity Check
# ============================================================
# Guards against the maintenance system itself becoming too complex.

echo "--- System Complexity ---"

# Count lines in the rules/config documentation
RULES_FILE="$WS/maintenance/optimization-rules.md"
RULES_LINES=0
if [ -f "$RULES_FILE" ]; then
  RULES_LINES=$(wc -l < "$RULES_FILE" | tr -d ' ')
fi
echo "  rules_doc: ${RULES_LINES} lines"
if [ "$RULES_LINES" -gt "$LIMIT_RULES_LINES" ]; then
  WARNINGS+=("rules_doc=${RULES_LINES} lines (>${LIMIT_RULES_LINES})")
  echo "  [WARN] exceeds ${LIMIT_RULES_LINES}-line limit"
fi

# Count maintenance files
MAINT_DIR="$WS/maintenance"
MAINT_FILES=0
if [ -d "$MAINT_DIR" ]; then
  MAINT_FILES=$(find "$MAINT_DIR" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')
fi
echo "  maintenance_files: $MAINT_FILES"
if [ "$MAINT_FILES" -gt "$LIMIT_MAINTENANCE_FILES" ]; then
  WARNINGS+=("maintenance files=$MAINT_FILES (>${LIMIT_MAINTENANCE_FILES})")
  echo "  [WARN] exceeds ${LIMIT_MAINTENANCE_FILES}-file limit"
fi

# Count maintenance scripts
SCRIPT_COUNT=$(find "$SCRIPT_DIR" -maxdepth 1 -name "*.sh" -type f 2>/dev/null | wc -l | tr -d ' ')
echo "  maintenance_scripts: $SCRIPT_COUNT"
echo ""

# ============================================================
# 5. Workspace Metrics (for trending)
# ============================================================

echo "--- Workspace Metrics ---"
TOTAL_WS_KB=$(du -sk "$WS" 2>/dev/null | cut -f1 || echo 0)
TOTAL_WS_MB=$((TOTAL_WS_KB / 1024))
echo "  workspace_total: ${TOTAL_WS_MB}MB"

CRON_JOB_COUNT=0
if [ "$CHECK_CRON_JOBS" = "true" ] && [ -f "$CRON_JOBS_FILE" ]; then
  CRON_JOB_COUNT=$(grep -c '"id"' "$CRON_JOBS_FILE" 2>/dev/null || echo 0)
fi
echo "  cron_jobs: $CRON_JOB_COUNT"

MEM_FILE_COUNT=0
if [ -d "$MEMORY_DIR" ]; then
  MEM_FILE_COUNT=$(find "$MEMORY_DIR" -type f -name "*.md" 2>/dev/null | wc -l | tr -d ' ')
fi
echo "  memory_files_total: $MEM_FILE_COUNT"

PROJECT_COUNT=0
if [ -d "$PROJECTS_DIR" ]; then
  PROJECT_COUNT=$(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
fi
echo "  projects: $PROJECT_COUNT"
echo ""

# ============================================================
# 6. Quarter Check
# ============================================================

echo "--- Quarter Status ---"
IS_QUARTER="false"
if [ $((10#$CURRENT_MONTH % 3)) -eq 0 ]; then
  IS_QUARTER="true"
  QUARTER=$(( (10#$CURRENT_MONTH - 1) / 3 + 1 ))
  echo "  Quarter month detected — seasonal analysis triggered"
  echo "  quarter: Q$QUARTER"
else
  echo "  Non-quarter month — seasonal analysis skipped"
fi
echo ""

# ============================================================
# 7. Database Maintenance
# ============================================================

echo "--- Database Maintenance ---"
EMBEDDINGS_DB="$MEMORY_DIR/main.sqlite"
if [ -f "$EMBEDDINGS_DB" ] && command -v sqlite3 &>/dev/null; then
  BEFORE_BYTES=$(file_size_bytes "$EMBEDDINGS_DB")
  BEFORE_MB=$((BEFORE_BYTES / 1048576))

  if [ "$BEFORE_MB" -gt 200 ]; then
    echo "  embeddings_db: ${BEFORE_MB}MB — running VACUUM..."
    sqlite3 "$EMBEDDINGS_DB" "VACUUM;" 2>/dev/null && {
      AFTER_BYTES=$(file_size_bytes "$EMBEDDINGS_DB")
      AFTER_MB=$((AFTER_BYTES / 1048576))
      echo "  result: ${BEFORE_MB}MB -> ${AFTER_MB}MB (saved $(( BEFORE_MB - AFTER_MB ))MB)"
    } || echo "  VACUUM failed"
  else
    echo "  embeddings_db: ${BEFORE_MB}MB (below 200MB threshold, skipping VACUUM)"
  fi
elif [ -f "$EMBEDDINGS_DB" ]; then
  BEFORE_BYTES=$(file_size_bytes "$EMBEDDINGS_DB")
  BEFORE_MB=$((BEFORE_BYTES / 1048576))
  echo "  embeddings_db: ${BEFORE_MB}MB (sqlite3 not available for VACUUM)"
else
  echo "  (no embeddings DB found)"
fi
echo ""

# ============================================================
# SUMMARY
# ============================================================

echo "--- Summary ---"
echo "  warnings: ${#WARNINGS[@]}"
echo "  is_quarter: $IS_QUARTER"
echo "  stale_topics: $STALE_TOPICS"
echo ""

if [ ${#WARNINGS[@]} -gt 0 ]; then
  echo "--- All Warnings ---"
  for w in "${WARNINGS[@]}"; do
    echo "  [WARN] $w"
  done
  echo ""
fi

echo "--- AI Tasks Remaining ---"
echo "  1. Environment manifest diff (compare snapshot above with stored manifest)"
echo "  2. Topic overlap detection (cross-compare topic file contents)"
echo "  3. Optimization suggestions review + rule adoption decisions"
echo "  4. System complexity assessment"
if [ "$IS_QUARTER" = "true" ]; then
  echo "  5. Seasonal trends analysis (workspace growth, usage patterns)"
fi
echo ""

echo "=== END ==="
