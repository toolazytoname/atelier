#!/usr/bin/env bash
# install.sh — one-line installer for Claude Code skills.
#
# Usage (public, for skill consumers):
#   curl -fsSL https://raw.githubusercontent.com/<owner>/<repo>/main/install.sh | bash
#
# Usage (local, for skill authors testing):
#   ./install.sh
#
# What it does:
#   1. Clones the skill repo to ~/.claude/skill-packages/<repo-name>
#   2. Symlinks each skill/ subdirectory into ~/.claude/skills/
#
# Safe by design:
#   - Pure bash, no dependencies beyond git
#   - Idempotent (re-run anytime)
#   - Only touches ~/.claude/skills/ and ~/.claude/skill-packages/
#   - Removes stale symlinks before recreating
#   - Never modifies anything outside ~/.claude/
#   - Exits on any error (set -euo pipefail)
#
# Audit this script before running:
#   curl -fsSL <url> | cat    # read it first
#   curl -fsSL <url> | bash   # then run it
set -euo pipefail

# ---------------------------------------------------------------------------
# Config — skill authors: edit these two lines
# ---------------------------------------------------------------------------
REPO_URL="${REPO_URL:-https://github.com/toolazytoname/atelier.git}"
REPO_REF="${REPO_REF:-main}"

# ---------------------------------------------------------------------------
# Derived (no edits needed below)
# ---------------------------------------------------------------------------
REPO_NAME="$(basename "$REPO_URL" .git)"
PACKAGES_DIR="${HOME}/.claude/skill-packages"
SKILLS_DIR="${HOME}/.claude/skills"
CLONE_DIR="${PACKAGES_DIR}/${REPO_NAME}"

# Colors (disabled when piped or NO_COLOR set)
if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
  C_BLUE='\033[1;34m' C_GREEN='\033[1;32m' C_YELLOW='\033[1;33m' C_RED='\033[1;31m' C_RESET='\033[0m'
else
  C_BLUE='' C_GREEN='' C_YELLOW='' C_RED='' C_RESET=''
fi

log()   { printf "${C_BLUE}[install]${C_RESET} %s\n" "$*"; }
ok()    { printf "${C_GREEN}[install]${C_RESET} %s\n" "$*"; }
warn()  { printf "${C_YELLOW}[install]${C_RESET} %s\n" "$*" >&2; }
die()   { printf "${C_RED}[install]${C_RESET} %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v git >/dev/null 2>&1 || die "git is required but not found in PATH"

# ---------------------------------------------------------------------------
# Clone or update
# ---------------------------------------------------------------------------
mkdir -p "$PACKAGES_DIR"

if [[ -d "$CLONE_DIR/.git" ]]; then
  log "updating $REPO_NAME ($REPO_REF)..."
  git -C "$CLONE_DIR" fetch origin "$REPO_REF" --quiet
  git -C "$CLONE_DIR" checkout "$REPO_REF" --quiet
  git -C "$CLONE_DIR" reset --hard "origin/$REPO_REF" --quiet
else
  log "cloning $REPO_URL ($REPO_REF)..."
  # Remove stale directory if it exists without .git
  rm -rf "$CLONE_DIR"
  git clone --branch "$REPO_REF" --depth 1 "$REPO_URL" "$CLONE_DIR" --quiet
fi

# ---------------------------------------------------------------------------
# Discover skills (any directory containing SKILL.md)
# ---------------------------------------------------------------------------
SKILL_DIRS=()
while IFS= read -r dir; do
  [[ -n "$dir" ]] && SKILL_DIRS+=("$dir")
done < <(find "$CLONE_DIR" -maxdepth 4 -name "SKILL.md" -exec dirname {} \; 2>/dev/null || true)

if [[ ${#SKILL_DIRS[@]} -eq 0 ]]; then
  die "no SKILL.md found in $CLONE_DIR — is this a skill repo?"
fi

# ---------------------------------------------------------------------------
# Install (symlink each skill into ~/.claude/skills/)
# ---------------------------------------------------------------------------
mkdir -p "$SKILLS_DIR"

INSTALLED=()
for skill_dir in "${SKILL_DIRS[@]}"; do
  skill_name="$(basename "$skill_dir")"
  link_target="$SKILLS_DIR/$skill_name"

  # Remove stale symlink or directory
  if [[ -L "$link_target" ]]; then
    rm -f "$link_target"
  elif [[ -d "$link_target" ]]; then
    warn "skipping $skill_name — directory already exists (not a symlink)"
    warn "  remove it manually: rm -rf $link_target"
    continue
  fi

  ln -s "$skill_dir" "$link_target"
  INSTALLED+=("$skill_name")
  ok "linked $skill_name → $skill_dir"
done

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
if [[ ${#INSTALLED[@]} -eq 0 ]]; then
  warn "no new skills installed (all already exist or skipped)"
else
  ok "installed ${#INSTALLED[@]} skill(s): ${INSTALLED[*]}"
  log "restart Claude Code to activate"
fi
