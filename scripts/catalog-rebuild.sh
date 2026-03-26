#!/bin/bash
# catalog-rebuild.sh — Rebuild workspace catalog from directory structure
#
# Scans projects/, skills/, and workflows/ directories, reads descriptions
# from context.md / SKILL.md / workflow headers, and generates a catalog.
#
# Usage:
#   bash scripts/catalog-rebuild.sh
#
# Output: writes catalog.md to workspace root

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/../config/config.sh"
if [ ! -f "$CONFIG_FILE" ]; then
  echo "ERROR: config.sh not found at $CONFIG_FILE" >&2
  exit 1
fi
source "$CONFIG_FILE"

TODAY=$(date +%Y-%m-%d)
OUTPUT="$WS/catalog.md"

# ── Helpers ──────────────────────────────────────────────────

# Read first non-empty, non-heading line after the first heading
get_context_desc() {
  local ctx="$1/context.md"
  if [ ! -f "$ctx" ]; then
    echo "(no description)"
    return
  fi
  local desc
  desc=$(awk '
    /^#/{found=1; next}
    found && /^[[:space:]]*$/{next}
    found && /^#/{exit}
    found{print; exit}
  ' "$ctx" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  if [ -z "$desc" ]; then
    echo "(no description)"
  else
    echo "$desc"
  fi
}

get_skill_desc() {
  local skill_md="$1/SKILL.md"
  [ ! -f "$skill_md" ] && skill_md="$1/README.md"
  if [ ! -f "$skill_md" ]; then
    echo "(no description)"
    return
  fi
  local desc
  desc=$(awk '
    /^#/{found=1; next}
    found && /^[[:space:]]*$/{next}
    found && /^#/{exit}
    found{print; exit}
  ' "$skill_md" | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  if [ -z "$desc" ]; then
    echo "(no description)"
  else
    echo "$desc"
  fi
}

get_workflow_desc() {
  local wf="$1"
  if [ ! -f "$wf" ]; then
    echo "(no description)"
    return
  fi
  local desc
  desc=$(head -1 "$wf" | sed 's/^#[[:space:]]*//' | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*$//')
  if [ -z "$desc" ]; then
    echo "(no description)"
  else
    echo "$desc"
  fi
}

# ── Build catalog ────────────────────────────────────────────

PROJ_COUNT=0
SKILL_COUNT=0
WF_COUNT=0

{
  echo "# Workspace Catalog"
  echo "> Auto-generated. Do not edit manually."
  echo ""

  # Projects
  echo "## Projects"
  if [ -d "$PROJECTS_DIR" ]; then
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      PNAME=$(basename "$d")
      DESC=$(get_context_desc "$d")
      echo "- \`${PNAME}/\` -- ${DESC}"
      PROJ_COUNT=$((PROJ_COUNT + 1))
    done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    [ "$PROJ_COUNT" -eq 0 ] && echo "- (none)"
  else
    echo "- (projects/ directory not found)"
  fi
  echo ""

  # Skills
  SKILLS_DIR="$WS/skills"
  echo "## Skills"
  if [ -d "$SKILLS_DIR" ]; then
    while IFS= read -r d; do
      [ -z "$d" ] && continue
      SNAME=$(basename "$d")
      DESC=$(get_skill_desc "$d")
      echo "- \`${SNAME}/\` -- ${DESC}"
      SKILL_COUNT=$((SKILL_COUNT + 1))
    done < <(find "$SKILLS_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)
    [ "$SKILL_COUNT" -eq 0 ] && echo "- (none)"
  else
    echo "- (skills/ directory not found)"
  fi
  echo ""

  # Workflows
  WORKFLOWS_DIR="$WS/workflows"
  echo "## Workflows"
  if [ -d "$WORKFLOWS_DIR" ]; then
    while IFS= read -r f; do
      [ -z "$f" ] && continue
      WNAME=$(basename "$f")
      DESC=$(get_workflow_desc "$f")
      echo "- \`${WNAME}\` -- ${DESC}"
      WF_COUNT=$((WF_COUNT + 1))
    done < <(find "$WORKFLOWS_DIR" -maxdepth 1 -name "*.md" -type f 2>/dev/null | sort)
    [ "$WF_COUNT" -eq 0 ] && echo "- (none)"
  else
    echo "- (workflows/ directory not found)"
  fi
  echo ""

  echo "---"
  echo "*Updated: ${TODAY}*"

} > "$OUTPUT"

echo "Catalog rebuilt: $OUTPUT"
echo "  projects:  $PROJ_COUNT"
echo "  skills:    $SKILL_COUNT"
echo "  workflows: $WF_COUNT"
