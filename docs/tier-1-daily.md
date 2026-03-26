# Tier 1: Daily Cleanup

> Deterministic cleanup. Rules are clear. Delete or keep. No AI needed.

## Purpose

The daily cleanup handles everything that can be decided by simple rules: is this file older than N days? Are there more than N backups? This is the workhorse that keeps your workspace from accumulating cruft.

## What It Cleans

| Category | Path Pattern | Rule | Method |
|----------|-------------|------|--------|
| Backup files | `*.bak` in workspace root | Keep newest 2, delete rest | trash/rm |
| Screenshots | `screen0_*.png` | Delete if >3 days old | trash |
| Temp files | `temp_*.txt`, `*.tmp`, `*.swp` | Delete if >3 days old | trash |
| Inbound media | `media/inbound/*` | Delete if >7 days old | trash |
| Outbound media | `media/outbound/*` (Monday only) | Delete if >7 days old | trash |
| Empty date dirs | `media/*/YYYY-MM-DD/` (empty) | Remove empty dirs | rmdir |
| Cron logs | `cron/runs/*.jsonl` | Delete if >14 days old | rm |
| Cron backups | `cron/jobs.json.bak.*` | Keep newest 2 | rm |

## Two-Level Early Exit

The script first does a quick scan to decide if a full cleanup is even needed.

```
Quick scan: any old temp files? old media? old cron logs?
  │
  ├─ Nothing to clean ──┬─ No warnings ──→ Level 2 exit (silent)
  │                     └─ Has warnings ──→ Level 1 exit (report warnings only)
  │
  └─ Has items to clean ──→ Full cleanup (phases 3-5)
```

**Why?** On a well-maintained workspace, most days the script finds nothing to do. The early exit avoids unnecessary filesystem scanning and keeps logs clean.

## Health Checks (Always Run)

Even on early exit, the script checks:
- Database sizes (warning if above threshold)
- Gateway status (optional, configurable)
- Memory file count
- Naming compliance (memory files should follow `YYYY-MM-DD.md` convention)

## AI Assessment Handoff

Some decisions require judgment. The daily script identifies these and outputs them in a structured section:

```
--- AI Assessment Needed ---
Scattered files (>3 days, need complete/in-progress judgment):
2025-03-15-research-notes.md
2025-03-12-meeting-decisions.md
```

These are memory files with date+topic suffixes that are old enough to archive, but the script cannot determine if they're still relevant. An AI agent or human reviews these.

## Scheduling

```bash
# Run daily at 2:00 AM
0 2 * * * /path/to/auto-optimization/scripts/daily-cleanup.sh >> /path/to/logs/daily.log 2>&1
```

## Safe Deletion

The script prefers `trash` (macOS) over `rm` for user-facing files. This gives you a safety net -- accidentally cleaned files can be recovered from Trash. Set `USE_TRASH=false` in config to disable.

Log files and cron runs use `rm` directly since they're system-generated and replaceable.

## Configuration

```bash
THRESHOLD_TEMP_DAYS=3       # Temp file age before deletion
THRESHOLD_MEDIA_DAYS=7      # Media file age before deletion
THRESHOLD_CRON_LOG_DAYS=14  # Cron log age before deletion
LIMIT_BAK_KEEP=2            # Backup files to retain
LIMIT_CRON_BAK_KEEP=2       # Cron backup files to retain
USE_TRASH=true              # Use trash instead of rm
```

## Sentinel File

On completion (including early exit), writes a timestamp to `.last-daily-ok`:

```
2025-03-27T02:35:04
```

This is how Tier 0 knows the daily job ran successfully.

## Common Customizations

**Add a new cleanup category:**
1. Add threshold to `config/config.sh`
2. Add a cleanup block in Phase 3 of `daily-cleanup.sh`
3. Add the counter to the output report

**Change the media inbound threshold to 14 days:**
```bash
# In config/config.sh
THRESHOLD_MEDIA_DAYS=14
```

**Disable outbound media cleanup entirely:**
Remove or comment out the `3b2: media/outbound` block in the script.
