# Tier 3: Monthly Deep Audit

> The big picture. Environment drift, system complexity, long-term trends.

## Purpose

Monthly audits catch slow-moving problems that daily and weekly checks miss: package drift, topic staleness, archive bloat, and the maintenance system's own complexity creep. This is also where quarterly trend analysis happens.

## What the Script Collects

### Environment Snapshot
A full inventory of installed packages, enabling manifest diffing:
- Homebrew formulas and casks (macOS)
- APT packages (Linux)
- npm/pip global packages
- Node and Python versions

Compare this against a stored manifest to detect:
- Packages installed but not documented
- Documented packages that were removed
- Version changes

### Topic Staleness
Topics not modified in >30 days may contain outdated information:

```
--- Topic Staleness ---
  [OK] delegation-ops.md: 5d
  [OK] formats.md: 12d
  [WARN] old-workflow.md: 45d since last modified
  stale_count: 1
```

### Archive Capacity
Monitor long-term storage growth:

```
--- Archive Capacity ---
  total: 12MB
  2025-01-early: 340KB (8 files)
  2025-01-late: 520KB (12 files)
  2025-02-early: 280KB (6 files)
```

### System Complexity Check
The maintenance system must not become more complex than the workspace it maintains:

| Metric | Limit | Why |
|--------|-------|-----|
| Rules documentation lines | 250 | If rules need >250 lines, they're too complex |
| Maintenance files | 15 | Too many files = too many moving parts |
| Maintenance scripts | reasonable | Each script should earn its keep |

### Database Maintenance
For workspaces with SQLite databases (e.g., embeddings, vector stores):
- Databases >200MB get `VACUUM`ed automatically
- Before/after sizes are reported

## AI Tasks (Post-Scan)

### 1. Manifest Diff
Compare the environment snapshot to a stored `MANIFEST.md`:
- New packages: add to manifest, note purpose
- Removed packages: remove from manifest
- Version changes: update

### 2. Topic Overlap Detection
Cross-compare topic files for redundant content:
- Two topics covering the same tool/concept: suggest merge
- Topic content duplicated in project docs: suggest dedup
- Only report, never auto-merge

### 3. Suggestions Finalization
Monthly handles structural changes that weekly deferred:
- New cleanup categories
- Architecture changes
- Safety rule modifications

### 4. Quarterly Analysis (March, June, September, December)
On quarter boundaries, additional analysis:
- Workspace size trend (is it growing? shrinking?)
- Project count trend
- Memory file count trend
- Which scheduled jobs run most/least frequently?

Output: a brief trends summary for long-term awareness.

## Sentinel

Written after all AI tasks complete:

```bash
echo "$(date +%Y-%m-%dT%H:%M:%S)" > maintenance/.last-monthly-ok
```

## Scheduling

```bash
# Run monthly on the 1st at 10:00 AM
0 10 1 * * /path/to/auto-optimization/scripts/monthly-scan.sh >> /path/to/logs/monthly.log 2>&1
```

## The Complexity Trap

A recurring theme in maintaining AI workspaces: the maintenance system itself grows complex. Monthly audits include a self-check:

```
--- System Complexity ---
  rules_doc: 180 lines
  maintenance_files: 12
  maintenance_scripts: 6
```

If these numbers creep up, it's a signal to simplify. The best maintenance system is the one you can understand in 10 minutes.

## Archive Strategy

Archives are never deleted, only compressed:

1. **Daily notes** (>14 days) get compressed by the weekly scan
2. **Originals** move to `archive/YYYY-MM-early/` or `archive/YYYY-MM-late/`
3. **Quarterly** (on quarter months), old archives get merged into summaries
4. The `archive-move.sh` helper handles the directory math

This ensures no information is lost while keeping the active workspace lean.
