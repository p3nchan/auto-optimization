# Tier 0: Hourly Health Checks

> Pure shell. No AI. No cost. Catches problems before they cascade.

## Purpose

The hourly health check is the foundation of the maintenance pyramid. It runs deterministic checks that require zero judgment -- just comparing numbers to thresholds. If something is wrong, it outputs a structured report that a human or AI agent can act on.

## What It Checks

| Check | What | Threshold | Action on Failure |
|-------|------|-----------|-------------------|
| Sentinel freshness | Did daily/weekly/monthly jobs run? | daily >26h, weekly >8d, monthly >32d | Warning |
| Log errors | Error/fatal entries in recent logs | Any in last hour | Warning |
| Cron failures | Failed scheduled job runs | Any in last hour | Warning |
| Memory file count | `.md` files in memory root | >25 | Warning |
| DB size | SQLite databases exceeding limits | Configurable per DB | Warning |
| Gateway health | HTTP check on local service | Unreachable | Warning |
| Error dedup | Same warning pattern repeating | 3+ consecutive | Escalate |

## Exit Codes

| Code | Meaning | Recommended Response |
|------|---------|---------------------|
| `0` | All clear | Do nothing |
| `1` | Warnings present | Log and/or notify |
| `2` | Errors present | Escalate to AI or human |

## Error Deduplication

A key feature: the script hashes its warning output and compares it to the previous run. If the same pattern appears:

- **1st-2nd repeat**: Suppressed (avoids alert fatigue)
- **3rd+ repeat**: Escalated with a note that it's a persistent issue

This prevents the common problem of the same non-critical warning flooding your notification channel every hour.

```
# How dedup works internally:
Run 1: "sentinel stale" → hash abc123, save hash, report warning
Run 2: "sentinel stale" → hash abc123, matches last, suppress (repeat #1)
Run 3: "sentinel stale" → hash abc123, matches last, suppress (repeat #2)
Run 4: "sentinel stale" → hash abc123, matches last, ESCALATE (repeat #3)
Run 5: "something else" → hash def456, new pattern, reset counter
```

## Scheduling

Run via cron every hour:

```bash
# crontab -e
0 * * * * /path/to/auto-optimization/scripts/hourly-healthcheck.sh >> /path/to/logs/hourly.log 2>&1
```

Or integrate with your AI agent's scheduler. The script is designed to be called by an orchestrator that reads the exit code:

```
exit 0 → skip (no action needed)
exit 1 → orchestrator logs the warning or sends a notification
exit 2 → orchestrator spawns an AI worker to investigate
```

## Configuration

All thresholds are in `config/config.sh`. Key settings:

```bash
SENTINEL_DAILY_STALE_HOURS=26   # Allow some buffer over 24h
SENTINEL_WEEKLY_STALE_DAYS=8    # Allow 1 day buffer
SENTINEL_MONTHLY_STALE_DAYS=32  # Allow 2 days buffer
LIMIT_MEMORY_MD_FILES=25        # Memory directory file cap
LIMIT_SQLITE_MB=10              # Workspace DB size warning
CHECK_GATEWAY=false             # Disable if no local gateway
```

## Design Decisions

**Why sentinel files instead of checking cron directly?**
Sentinels are file-based and framework-agnostic. Whether you use cron, systemd timers, or an AI agent scheduler, the maintenance scripts write a timestamp file when they complete. The hourly check just reads timestamps -- no need to understand your scheduling system.

**Why not auto-fix?**
Tier 0 only reports. If the daily job is stale, maybe your machine was asleep. If the DB is large, maybe it's supposed to be. Judgment calls belong in Tier 2 (AI-assisted) or with a human.
