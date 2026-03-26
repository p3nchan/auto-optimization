#!/bin/bash
# config.sh — Single Source of Truth for all optimization thresholds
#
# All scripts source this file. To change a threshold, change it HERE.
# Keep your documentation in sync if you reference specific numbers.
#
# Usage: source this file from any maintenance script
#   SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
#   source "$SCRIPT_DIR/../config/config.sh"

# ============================================================
# WORKSPACE ROOT — set this to your agent workspace path
# ============================================================

WS="${WORKSPACE_ROOT:-$HOME/.agent-workspace}"

# ============================================================
# Derived paths (override any of these via environment variables)
# ============================================================

MEMORY_DIR="${MEMORY_DIR:-$WS/memory}"
TOPICS_DIR="${TOPICS_DIR:-$MEMORY_DIR/topics}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$MEMORY_DIR/archive}"
PROJECTS_DIR="${PROJECTS_DIR:-$WS/projects}"
LOGS_DIR="${LOGS_DIR:-$WS/logs}"
CRON_DIR="${CRON_DIR:-$WS/cron}"
MEDIA_DIR="${MEDIA_DIR:-$WS/media}"
TMP_DIR="${TMP_DIR:-$WS/tmp}"

# ============================================================
# Time thresholds (days)
# ============================================================

# How old temp files (.tmp, .swp, screenshots) must be before deletion
THRESHOLD_TEMP_DAYS="${THRESHOLD_TEMP_DAYS:-3}"

# How old media/inbound files must be before deletion
THRESHOLD_MEDIA_DAYS="${THRESHOLD_MEDIA_DAYS:-7}"

# How old cron run logs must be before deletion
THRESHOLD_CRON_LOG_DAYS="${THRESHOLD_CRON_LOG_DAYS:-14}"

# How old daily notes must be before compression is considered
THRESHOLD_COMPRESS_DAYS="${THRESHOLD_COMPRESS_DAYS:-14}"

# How old screenshots must be before deletion
THRESHOLD_SCREENSHOT_DAYS="${THRESHOLD_SCREENSHOT_DAYS:-3}"

# ============================================================
# Count limits
# ============================================================

# Max .bak files to keep in workspace root (oldest deleted first)
LIMIT_BAK_KEEP="${LIMIT_BAK_KEEP:-2}"

# Max cron backup files to keep
LIMIT_CRON_BAK_KEEP="${LIMIT_CRON_BAK_KEEP:-2}"

# Max .md files allowed in memory/ root before warning
LIMIT_MEMORY_MD_FILES="${LIMIT_MEMORY_MD_FILES:-25}"

# Max topic files before warning
LIMIT_TOPIC_FILES="${LIMIT_TOPIC_FILES:-10}"

# Max files in maintenance/ root (complexity check)
LIMIT_MAINTENANCE_FILES="${LIMIT_MAINTENANCE_FILES:-15}"

# Max lines in optimization-rules.md (complexity check)
LIMIT_RULES_LINES="${LIMIT_RULES_LINES:-250}"

# ============================================================
# Size limits
# ============================================================

# SQLite DB size warning threshold (MB)
LIMIT_SQLITE_MB="${LIMIT_SQLITE_MB:-10}"

# Embeddings DB expected size (MB) — large is normal for vector DBs
LIMIT_EMBEDDINGS_MB="${LIMIT_EMBEDDINGS_MB:-500}"

# Individual topic file hard limit (bytes, 1.5KB)
LIMIT_TOPIC_SIZE_BYTES="${LIMIT_TOPIC_SIZE_BYTES:-1536}"

# Canvas directory warning threshold (MB)
LIMIT_CANVAS_MB="${LIMIT_CANVAS_MB:-20}"

# Media subdirectory warning threshold (MB)
LIMIT_MEDIA_SUBDIR_MB="${LIMIT_MEDIA_SUBDIR_MB:-50}"

# Archive total size warning threshold (MB)
LIMIT_ARCHIVE_MB="${LIMIT_ARCHIVE_MB:-50}"

# ============================================================
# Sentinel file staleness thresholds
# ============================================================

# Hours before daily sentinel is considered stale
SENTINEL_DAILY_STALE_HOURS="${SENTINEL_DAILY_STALE_HOURS:-26}"

# Days before weekly sentinel is considered stale
SENTINEL_WEEKLY_STALE_DAYS="${SENTINEL_WEEKLY_STALE_DAYS:-8}"

# Days before monthly sentinel is considered stale
SENTINEL_MONTHLY_STALE_DAYS="${SENTINEL_MONTHLY_STALE_DAYS:-32}"

# ============================================================
# Sentinel file paths
# ============================================================

SENTINEL_DIR="${SENTINEL_DIR:-$WS/maintenance}"
SENTINEL_DAILY="$SENTINEL_DIR/.last-daily-ok"
SENTINEL_WEEKLY="$SENTINEL_DIR/.last-weekly-ok"
SENTINEL_MONTHLY="$SENTINEL_DIR/.last-monthly-ok"

# ============================================================
# Feature flags
# ============================================================

# Use `trash` command instead of `rm` when available (macOS)
USE_TRASH="${USE_TRASH:-true}"

# Enable gateway health check (disable if you don't run a local gateway)
CHECK_GATEWAY="${CHECK_GATEWAY:-false}"

# Gateway URL for health check
GATEWAY_URL="${GATEWAY_URL:-http://127.0.0.1:8080}"

# Enable cron job health monitoring
CHECK_CRON_JOBS="${CHECK_CRON_JOBS:-true}"

# Path to cron jobs definition file (JSON)
CRON_JOBS_FILE="${CRON_JOBS_FILE:-$CRON_DIR/jobs.json}"

# ============================================================
# Platform detection
# ============================================================

PLATFORM="unknown"
case "$(uname -s)" in
  Darwin*) PLATFORM="macos" ;;
  Linux*)  PLATFORM="linux" ;;
esac

# Date command compatibility
# macOS uses `date -v-7d`, Linux uses `date -d '7 days ago'`
date_ago() {
  local days="$1"
  local format="${2:-%Y-%m-%d}"
  if [ "$PLATFORM" = "macos" ]; then
    date -v-${days}d +"$format"
  else
    date -d "${days} days ago" +"$format"
  fi
}

# File size in bytes (cross-platform)
file_size_bytes() {
  local filepath="$1"
  if [ "$PLATFORM" = "macos" ]; then
    stat -f%z "$filepath" 2>/dev/null || echo "0"
  else
    stat -c%s "$filepath" 2>/dev/null || echo "0"
  fi
}

# File modification epoch (cross-platform)
file_mtime_epoch() {
  local filepath="$1"
  if [ "$PLATFORM" = "macos" ]; then
    stat -f "%m" "$filepath" 2>/dev/null || echo "0"
  else
    stat -c "%Y" "$filepath" 2>/dev/null || echo "0"
  fi
}

# Parse ISO 8601 timestamp to epoch (cross-platform)
iso_to_epoch() {
  local ts="$1"
  if [ "$PLATFORM" = "macos" ]; then
    date -jf "%Y-%m-%dT%H:%M:%S" "$ts" +%s 2>/dev/null || echo "0"
  else
    date -d "$ts" +%s 2>/dev/null || echo "0"
  fi
}
