<p align="center">
  <img src="assets/banner.webp" alt="Auto Optimization" width="100%">
</p>

# Auto Optimization

> **🇹🇼 中文網頁版** — [penchan.co/ai/auto-optimization](https://penchan.co/ai/auto-optimization/)

**Automated workspace hygiene for AI agent workspaces.** Born from managing a workspace with 100+ files changing daily across 20+ projects, multiple AI agents, and scheduled jobs running around the clock.

The core insight: **scripts do deterministic work, AI only handles judgment calls.** This separation keeps costs near zero for routine maintenance while reserving expensive AI time for decisions that actually require intelligence.

## The Problem

AI agent workspaces accumulate cruft fast:
- Temporary files from every session
- Screenshots, media, and artifacts that outlive their purpose
- Memory files that grow unbounded
- Cron logs from dozens of scheduled jobs
- Topic files that drift out of date
- The maintenance system itself becoming more complex than the workspace

Without automated hygiene, you spend the first 10 minutes of every session cleaning up the last one.

<img src="assets/sections/architecture.webp" alt="Architecture" width="100%">

## Architecture: Four Tiers

```
Tier 0  Hourly     Shell only    $0      Sentinel checks, log errors, dedup
Tier 1  Daily      Shell only    $0      Delete old temps, media, logs
Tier 2  Weekly     Shell + AI    ~$0.01  Topic refinement, note compression
Tier 3  Monthly    Shell + AI    ~$0.05  Manifest diff, complexity audit
```

Each tier runs a shell script that outputs structured data. Tiers 0-1 are fully autonomous. Tiers 2-3 produce reports for an AI agent or human to review and act on.

**Key mechanisms:**
- **Sentinel files** — Each tier writes a timestamp on completion. The hourly check detects if any tier stopped running.
- **Early exit** — If the workspace is clean, scripts exit in milliseconds instead of scanning everything.
- **Error dedup** — Same warning pattern suppressed until 3rd consecutive occurrence, preventing alert fatigue.
- **Optimization suggestions loop** — Scripts discover gaps in their own rules and propose fixes for the next review cycle.

<img src="assets/sections/scripts.webp" alt="Scripts" width="100%">

## Quick Start

### 1. Clone and configure

```bash
git clone https://github.com/p3nchan/auto-optimization.git
cd auto-optimization

# Set your workspace path
export WORKSPACE_ROOT="$HOME/.my-agent-workspace"

# Or edit config/config.sh directly:
# WS="${WORKSPACE_ROOT:-$HOME/.agent-workspace}"
```

### 2. Review thresholds

Open `config/config.sh` and adjust thresholds to match your workspace:

```bash
THRESHOLD_TEMP_DAYS=3        # Delete temp files older than 3 days
THRESHOLD_MEDIA_DAYS=7       # Delete media older than 7 days
THRESHOLD_CRON_LOG_DAYS=14   # Delete cron logs older than 14 days
LIMIT_MEMORY_MD_FILES=25     # Warn if >25 notes in memory/
LIMIT_TOPIC_FILES=10         # Warn if >10 topic files
```

### 3. Run manually first

```bash
# Check workspace health
bash scripts/hourly-healthcheck.sh
echo "Exit code: $?"

# Preview what daily cleanup would do
bash scripts/daily-cleanup.sh

# Collect weekly scan data
bash scripts/weekly-scan.sh
```

### 4. Schedule with cron

```bash
crontab -e
```

```cron
# Tier 0: Hourly health check
0 * * * * cd /path/to/auto-optimization && bash scripts/hourly-healthcheck.sh >> /tmp/auto-opt-hourly.log 2>&1

# Tier 1: Daily cleanup at 2 AM
0 2 * * * cd /path/to/auto-optimization && bash scripts/daily-cleanup.sh >> /tmp/auto-opt-daily.log 2>&1

# Tier 2: Weekly scan on Sunday 9 AM (review output manually or pipe to AI)
0 9 * * 0 cd /path/to/auto-optimization && bash scripts/weekly-scan.sh >> /tmp/auto-opt-weekly.log 2>&1

# Tier 3: Monthly scan on the 1st at 10 AM
0 10 1 * * cd /path/to/auto-optimization && bash scripts/monthly-scan.sh >> /tmp/auto-opt-monthly.log 2>&1
```

### 5. Optional: Connect to your AI agent

The scripts are designed to be called by an AI orchestrator. Example pattern:

```bash
# In your AI agent's scheduler:
OUTPUT=$(bash scripts/hourly-healthcheck.sh 2>&1)
EXIT_CODE=$?

case $EXIT_CODE in
  0) ;; # All clear, do nothing
  1) notify "Warning: $OUTPUT" ;;  # Log or send notification
  2) spawn_ai_worker "$OUTPUT" ;;  # AI investigates and fixes
esac
```

For weekly/monthly scans, pipe the full output to your AI agent as context:

```bash
SCAN=$(bash scripts/weekly-scan.sh 2>&1)
ai_agent_prompt "Review this weekly scan and perform the listed AI tasks:\n$SCAN"
```

## Directory Layout

```
auto-optimization/
├── README.md
├── LICENSE                          # MIT
├── config/
│   └── config.sh                   # All thresholds, paths, platform detection
├── scripts/
│   ├── hourly-healthcheck.sh       # Tier 0: sentinel + log + resource checks
│   ├── daily-cleanup.sh            # Tier 1: deterministic file cleanup
│   ├── weekly-scan.sh              # Tier 2: comprehensive data collection
│   ├── monthly-scan.sh             # Tier 3: deep audit + environment snapshot
│   ├── archive-move.sh             # Helper: move notes to dated archive dirs
│   └── catalog-rebuild.sh          # Helper: rebuild workspace catalog
├── docs/
│   ├── architecture.md             # System design and data flow
│   ├── tier-0-hourly.md            # Hourly check documentation
│   ├── tier-1-daily.md             # Daily cleanup documentation
│   ├── tier-2-weekly.md            # Weekly AI-assisted scan documentation
│   └── tier-3-monthly.md           # Monthly deep audit documentation
└── templates/
    ├── optimization-rules.md       # Cleanup rules template
    ├── optimization-suggestions.md # Feedback loop template
    └── MANIFEST.md                 # Environment manifest template
```

## Workspace Structure

The scripts expect (but don't require) this workspace layout. All paths are configurable in `config/config.sh`:

```
$WORKSPACE_ROOT/
├── memory/              # Notes and knowledge
│   ├── *.md             # Daily notes (YYYY-MM-DD.md)
│   ├── topics/          # Stable knowledge files
│   └── archive/         # Compressed old notes
├── projects/            # Project directories (each with context.md + status.md)
├── media/               # Media files (inbound/ and outbound/)
├── cron/                # Scheduled jobs (jobs.json + runs/)
├── logs/                # Application logs
├── skills/              # AI skill/tool definitions
├── workflows/           # Workflow definitions
├── maintenance/         # Sentinel files live here
└── catalog.md           # Auto-generated workspace index
```

Missing directories are handled gracefully -- the scripts skip checks for paths that don't exist.

## Platform Support

| Feature | macOS | Linux |
|---------|-------|-------|
| Date arithmetic | `date -v` | `date -d` |
| File stats | `stat -f` | `stat -c` |
| Safe delete | `trash` (falls back to `rm`) | `rm` |
| Homebrew audit | Yes | N/A (uses `apt` instead) |

Cross-platform helpers (`date_ago`, `file_size_bytes`, `file_mtime_epoch`, `iso_to_epoch`) are defined in `config/config.sh`. The scripts auto-detect the platform.

## Lessons from Production

These patterns emerged from months of real operation:

1. **`-newermt` over `-mtime`**: The `-mtime` flag calculates in 24-hour blocks with unintuitive boundary behavior. We switched after discovering that `find -mtime +7` missed files that `find -not -newermt` caught. The difference: 2 files vs 18.

2. **Null byte bug**: Bash variables cannot store null bytes. `deleted_files=$(find ... -print0)` followed by `echo "$deleted_files" | xargs -0` silently concatenates all paths into one giant string. Fix: pipe `find` directly into a `while read` loop.

3. **Early exit saves real time**: On a clean workspace, the daily script finishes in <100ms instead of scanning thousands of files. Most days, nothing needs cleaning.

4. **Error dedup prevents alert blindness**: Without dedup, a non-critical warning (like a DB slightly above threshold) fires every hour forever. With dedup, you see it once, then again only if it persists for 3+ checks.

5. **The maintenance system itself needs limits**: We set hard caps on the rules file (250 lines), maintenance directory (15 files), and cron jobs (5). When the system to maintain the system gets too complex, it's time to simplify.

6. **Sentinel > cron status**: Checking "did the job write its success marker?" is more reliable than checking "did cron run the job?" because cron can run a job that fails silently.

7. **AI reviews, scripts collect**: An AI agent reading a structured scan report makes better decisions than an AI agent running `find` commands itself. The script handles filesystem details; the AI handles semantic understanding.

## Customization

### Adding a new cleanup category

1. Add threshold to `config/config.sh`:
   ```bash
   THRESHOLD_JUPYTER_DAYS="${THRESHOLD_JUPYTER_DAYS:-7}"
   ```

2. Add cleanup logic to `scripts/daily-cleanup.sh` (Phase 3):
   ```bash
   # --- Jupyter checkpoints ---
   JUPYTER_DELETED=0
   if [ -d "$WS/.ipynb_checkpoints" ]; then
     JUPYTER_DELETED=$(find "$WS" -name ".ipynb_checkpoints" -type d \
       -not -newermt "$(date_ago $THRESHOLD_JUPYTER_DAYS)" -print0 \
       | delete_find_results rm)
     ACTIONS=$((ACTIONS + JUPYTER_DELETED))
   fi
   ```

3. Add to output report and document in your rules file.

### Disabling features

```bash
# In config/config.sh or via environment:
export CHECK_GATEWAY=false      # Skip gateway health checks
export CHECK_CRON_JOBS=false    # Skip cron job monitoring
export USE_TRASH=false          # Use rm instead of trash
```

### Integrating with Claude Code / Cursor / other AI tools

The weekly and monthly scan outputs are designed as AI prompts. Feed the output directly to your AI agent:

```
You are a workspace maintenance agent. Review this scan output and:
1. Identify which topic files need updating based on recent daily notes
2. List daily notes that should be compressed (extract key decisions only)
3. Flag any project health issues that need attention
4. Review pending optimization suggestions and recommend adopt/ignore

[paste scan output here]
```

## Contributing

Contributions welcome. The system is intentionally minimal -- complexity should decrease over time, not increase.

Before adding a new feature, ask: "Can this be handled by an existing tier?" If yes, add a check there instead of creating a new script.

## License

MIT
