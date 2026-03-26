# Architecture

## Design Principle

> Scripts do deterministic work. AI only handles judgment calls.

This separation exists because:
1. **Shell scripts are free.** AI API calls cost money and tokens.
2. **Deterministic tasks don't need AI.** "Delete files older than 7 days" is a rule, not a judgment.
3. **AI mistakes are contained.** Scripts collect data; AI reviews it. A hallucinating model can't accidentally delete your files because it never has delete permissions in the scan phase.
4. **It's auditable.** Every cleanup has a paper trail in structured output.

## The Four Tiers

```
Tier 0: Hourly      ─── Shell script ──── Zero cost
  │ Sentinel checks, log errors, resource usage, error dedup
  │
Tier 1: Daily       ─── Shell script ──── Zero cost
  │ Delete old temps, media, logs. Early exit if clean.
  │
Tier 2: Weekly      ─── Shell + AI ────── AI reviews scan output
  │ Topic refinement, note compression, project health, suggestions
  │
Tier 3: Monthly     ─── Shell + AI ────── AI reviews scan output
    Manifest diff, topic overlap, complexity check, quarterly trends
```

## Data Flow

```
┌─────────────────────────────────────────────────────────┐
│                    config/config.sh                       │
│         (Single Source of Truth for all thresholds)       │
└────────────────────────┬────────────────────────────────┘
                         │ sourced by
         ┌───────────────┼───────────────┐
         │               │               │
    ┌────▼────┐    ┌─────▼─────┐   ┌─────▼──────┐
    │ hourly  │    │   daily   │   │  weekly /  │
    │ health  │    │  cleanup  │   │  monthly   │
    │ check   │    │           │   │   scan     │
    └────┬────┘    └─────┬─────┘   └─────┬──────┘
         │               │               │
    exit code       exit code        structured
    0/1/2          0/1              report (stdout)
         │               │               │
         ▼               ▼               ▼
    ┌─────────┐   ┌───────────┐   ┌───────────┐
    │  alert  │   │ sentinel  │   │ AI agent  │
    │ or skip │   │  written  │   │ or human  │
    └─────────┘   └───────────┘   │  reviews  │
                                  └─────┬─────┘
                                        │
                                  sentinel written
                                  after AI completes
```

## Sentinel Files

Sentinel files are the heartbeat mechanism. Each tier writes a timestamp file when it completes:

```
maintenance/.last-daily-ok     → "2025-03-27T02:35:04"
maintenance/.last-weekly-ok    → "2025-03-24T09:20:53"
maintenance/.last-monthly-ok   → "2025-03-01T10:15:22"
```

The hourly check reads these to verify each tier is running on schedule. If a sentinel is stale, something went wrong -- the job crashed, the machine was off, or the AI agent didn't finish.

**Key distinction:** Daily writes its sentinel from the script (cleanup is fully automated). Weekly and monthly sentinels should be written only after the AI review completes, not after the scan script finishes.

## Error Dedup

The hourly check hashes its warning output and tracks consecutive repeats:

```
.last-error-hash        → SHA-256 of warning text
.error-repeat-count     → Number of consecutive matches
```

1st-2nd repeat: suppressed. 3rd+: escalated. New pattern: counter resets.

This prevents alert fatigue from known, non-critical issues (e.g., a DB that's always slightly above threshold).

## Optimization Suggestions Loop

A feedback mechanism between tiers:

```
Daily cleanup runs → notices something rules don't cover
  → writes suggestion to templates/optimization-suggestions.md

Weekly AI review → reads pending suggestions
  → adopts safe changes (threshold tweaks) immediately
  → defers structural changes to monthly

Monthly AI review → reviews structural suggestions
  → adopts, ignores, or requests human input
  → cleans up old resolved suggestions
```

This creates an evolutionary loop: the system discovers its own gaps and proposes fixes.

## Cross-Platform Support

All scripts use helper functions from `config.sh` for platform-specific operations:

| Operation | macOS | Linux |
|-----------|-------|-------|
| Date arithmetic | `date -v-7d` | `date -d '7 days ago'` |
| File size | `stat -f%z` | `stat -c%s` |
| File mtime | `stat -f "%m"` | `stat -c "%Y"` |
| Safe delete | `trash` (if available) | `rm` |
| Timestamp parse | `date -jf` | `date -d` |

The `date_ago`, `file_size_bytes`, `file_mtime_epoch`, and `iso_to_epoch` functions abstract these differences.

## Directory Structure Assumptions

The scripts expect this workspace layout (all paths configurable):

```
$WS/                          # Workspace root
├── memory/                   # Notes, daily logs, knowledge
│   ├── *.md                  # Daily notes (YYYY-MM-DD.md)
│   ├── topics/               # Stable knowledge files
│   ├── archive/              # Compressed old notes
│   │   ├── YYYY-MM-early/    # Days 1-15
│   │   └── YYYY-MM-late/     # Days 16-31
│   └── MEMORY.md             # Index (optional)
├── projects/                 # Project directories
│   └── */context.md          # Project context
│   └── */status.md           # Project status
├── media/                    # Media files
│   ├── inbound/              # Received files
│   └── outbound/             # Generated files
├── cron/                     # Scheduled jobs
│   ├── jobs.json             # Job definitions
│   └── runs/                 # Execution logs
├── logs/                     # Application logs
├── skills/                   # AI skill definitions
├── workflows/                # Workflow definitions
├── maintenance/              # This system's config
│   ├── .last-daily-ok        # Sentinel files
│   ├── .last-weekly-ok
│   └── .last-monthly-ok
└── catalog.md                # Auto-generated index
```

Not all directories need to exist. Scripts gracefully handle missing paths.
