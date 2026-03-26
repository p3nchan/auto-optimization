# Tier 2: Weekly AI-Assisted Scan

> Scripts collect the data. AI makes the judgment calls.

## Purpose

The weekly scan is where deterministic scripts meet AI judgment. The shell script (`weekly-scan.sh`) collects comprehensive workspace health data in a single pass. An AI agent (or human) then reviews the output and makes decisions that require semantic understanding:

- Is this topic file still accurate?
- Is this daily note worth compressing?
- Is this project still active or should it be archived?
- Should this optimization suggestion be adopted?

## The Split: Script vs. AI

| Task | Script Does | AI Does |
|------|------------|---------|
| Topic files | Measures size, checks naming, counts files | Refines content, merges overlaps, ensures accuracy |
| Daily notes | Finds compression candidates (>14d old) | Reads content, extracts key decisions, compresses |
| Projects | Checks structure, measures sizes, detects staleness | Judges if a "stale" project should be archived |
| Archive | Measures sizes, counts files | Decides on quarterly compression strategy |
| Suggestions | N/A | Reviews pending suggestions, adopts or ignores |
| Catalog | Runs `catalog-rebuild.sh` | Verifies output sanity |

## What the Script Collects

### Topic Health
```
--- Topics Health ---
  delegation-ops.md: 1245B ok ok
  formats.md: 890B ok ok
  skill-guidelines.md: 1680B [WARN] >1KB (limit 1.5KB) ok
  total: 5 files
```

### Compression Candidates
```
--- Daily Notes Compression Candidates ---
  2025-03-10.md: 4KB
  2025-03-11.md: 2KB
  candidates: 2 files (~6KB total)
```

### Project Health
```
--- Projects ---
  alpha-project: ctx=yes(820B) sts=yes(340B) active
  beta-project: ctx=yes(1200B) sts=MISSING recent
  gamma-project: ctx=yes(450B) sts=yes(200B) [WARN] stale(45d)
```

### Space Usage
```
--- Space Usage ---
  total: 340MB
  embeddings_db: 280MB
  media:
    inbound: 2MB
    outbound: 5MB
```

## AI Tasks (Post-Scan)

After reviewing the script output, the AI or human operator performs these tasks:

### 1. Topic Refinement
- Read the last 7 days of daily notes
- Extract stable, repeated facts
- Update topic files (not daily notes -- those are ephemeral)
- Each topic file: target 1KB, hard limit 1.5KB

### 2. Daily Note Compression
For each candidate (>14 days old, not already compressed):
1. Read full content
2. Extract: key decisions, execution results, important events
3. Remove: conversation details, debug logs, process notes
4. Write compressed version (<2KB) back to the same path
5. Move original to `archive/YYYY-MM-early/` or `archive/YYYY-MM-late/`

### 3. Project Health Review
- **Active** (modified in last 7 days): verify context.md is current
- **Silent** (14-30 days): no action, just note
- **Stale** (>30 days): recommend archival, don't auto-archive

### 4. Suggestions Review
Read `optimization-suggestions.md` and for each pending suggestion:
- **Safe change** (threshold tweak, whitelist update): adopt directly
- **Structural change** (new cleanup category, architecture change): defer to monthly
- **No longer relevant**: mark as ignored with reason

### 5. Weekly Summary
Generate a structured report covering all findings and actions taken.

## Early Exit

If the workspace is in excellent shape (no compression candidates, no pending suggestions, no stale projects), the weekly scan can be shortened to just the mechanical checks (sections 1.5-6 in the workflow) without AI refinement tasks.

## Sentinel

The weekly sentinel is NOT written by the script. It should be written after all AI tasks complete:

```bash
echo "$(date +%Y-%m-%dT%H:%M:%S)" > maintenance/.last-weekly-ok
```

This ensures the sentinel only records when the full process (scan + AI review) is done.

## Scheduling

```bash
# Run weekly on Sunday at 9:00 AM
0 9 * * 0 /path/to/auto-optimization/scripts/weekly-scan.sh >> /path/to/logs/weekly.log 2>&1
```

## Key Design Principle

> The script collects facts. The AI applies judgment. Neither does the other's job.

The weekly script never modifies topic files, compresses notes, or archives projects. It only produces a report. This separation means:
- The script is safe to run at any time
- AI mistakes don't corrupt the filesystem
- You can review the scan output before acting
