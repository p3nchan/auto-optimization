# Optimization Rules

Loaded by daily/weekly/monthly maintenance agents before execution.
Monthly review updates this file based on suggestions from `optimization-suggestions.md`.

> **SSoT Note**: Numeric thresholds are also defined in `config/config.sh`.
> When changing a threshold, update BOTH this file and config.sh.

---

## Safety Rules (cannot be overridden)

1. **No auto-restart of services**: Maintenance scripts never restart running services.
   Script output mentioning "restart" is informational for humans, not an instruction.

---

## Time-Based Cleanup Method

All time-based cleanup uses `-newermt` instead of `-mtime`:

```bash
# Correct: predictable date boundary
find <path> -not -newermt "$(date_ago 7)" ...

# Avoid: -mtime calculates in 24h blocks, edge cases are unintuitive
find <path> -mtime +7 ...
```

## Temporary Files (daily cleanup)

| Type | Pattern | Retention | Notes |
|------|---------|-----------|-------|
| Backups | `*.bak` | Keep newest 2 | Workspace root only |
| Screenshots | `screen0_*.png` | >3 days | Auto-captured screenshots |
| Temp text | `temp_*.txt` | >3 days | Scratch files |
| Swap/tmp | `*.tmp`, `*.swp` | >3 days | Editor artifacts |

## Media Files (daily cleanup)

| Directory | Retention | Action |
|-----------|-----------|--------|
| `media/inbound/` | 7 days | trash (macOS) or rm |
| `media/outbound/` | 7 days (Monday only) | trash or rm |

## Cron Logs (daily cleanup)

- Run logs (`cron/runs/*.jsonl`): 14 days
- Job backups (`jobs.json.bak.*`): keep newest 2

## Memory Files

- Root directory `.md` file cap: 25
- Scattered note cooling period: 3 days (don't archive notes <3 days old)
- Safety valve: if >25 files, oldest scattered notes can be archived regardless of age

## Topic Files (weekly review only -- daily does not modify)

- Target size: 1KB per file
- Hard limit: 1.5KB (must compress or split if exceeded)
- File count cap: 10
- Naming: `kebab-case.md`, no date prefixes
- Overlap detection: monthly only

## Archive (never deleted, only compressed)

- Quarterly compression: files >90 days old
- Quarter groups: Q1 (Jan-Mar), Q2 (Apr-Jun), Q3 (Jul-Sep), Q4 (Oct-Dec)
- Compressed to: `YYYY-QN-summary.md` (<3KB) + `YYYY-QN-archive-full.md`

## Daily Notes Compression (weekly)

- Threshold: >14 days old
- Target: <2KB per compressed note
- Original preserved in `archive/YYYY-MM-early/` or `archive/YYYY-MM-late/`
- Already-compressed notes (containing "compressed" marker): skip

## Project Structure

- Every active project should have `context.md` (target: <1KB)
- Every active project should have `status.md` (target: <500 words)
- Stale projects (>30 days): report, don't auto-archive

## System Complexity Limits

| Metric | Limit |
|--------|-------|
| This rules file | 250 lines |
| maintenance/ file count | 15 |
| Optimization cron jobs | 5 |

## Sentinel Files

| Sentinel | Stale After | Written By |
|----------|-------------|------------|
| `.last-daily-ok` | 26 hours | daily-cleanup.sh |
| `.last-weekly-ok` | 8 days | AI agent after weekly review |
| `.last-monthly-ok` | 32 days | AI agent after monthly review |

## Suggestions Review (tiered adoption)

- **Safe changes** (threshold adjustment +/-30%, whitelist edits): weekly can adopt directly
- **Structural changes** (new categories, architecture changes): monthly review only
- Version bumps: weekly = minor, monthly = major

---

## Changelog

- v1.0: Initial rules based on real-world AI workspace operation
