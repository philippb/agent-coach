#!/usr/bin/env bash
set -euo pipefail

# ── Upgrade mode detection ────────────────────────────────────────────────────
# When AGENT_COACH_UPGRADE=1, skip all prompts and use environment variables
if [[ "${AGENT_COACH_UPGRADE:-}" == "1" ]]; then
  UPGRADE_MODE=true
  USER_NAME="${AGENT_COACH_USER_NAME:?Required in upgrade mode}"
  PERSONALITY="${AGENT_COACH_PERSONALITY:-Flint}"
  COACH_NAME="${AGENT_COACH_COACH_NAME:-flint}"
  STYLE="${AGENT_COACH_STYLE:-balanced}"
  OPINION="${AGENT_COACH_OPINION:-moderate}"
  SELF_ASSESSMENT="${AGENT_COACH_SELF_ASSESSMENT:-}"
  TARGETS_SELECTED="${AGENT_COACH_TARGETS:-${AGENT_COACH_TARGET:-codex}}"
else
  UPGRADE_MODE=false
fi

if [ -z "${BASH_VERSION:-}" ]; then
  echo "This script requires bash. Run with: bash install.sh" >&2
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Agent Coach — Your AI Prompting Mentor
# One-liner install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/philippb/agent-coach/main/install.sh)
# ─────────────────────────────────────────────────────────────────────────────

STATE_DIR="$HOME/.agent-coach"
CODEX_HOME_DIR="${CODEX_HOME:-$HOME/.codex}"
CODEX_SKILLS_DIR="${CODEX_HOME_DIR}/skills"
# Read version from VERSION file; fall back to embedded version for curl installs.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EMBEDDED_VERSION=2
VERSION="$EMBEDDED_VERSION"
if [[ -f "${SCRIPT_DIR}/VERSION" ]]; then
  VERSION=$(cat "${SCRIPT_DIR}/VERSION" 2>/dev/null || echo "$EMBEDDED_VERSION")
fi
PARTIAL_INSTALL=false
MIGRATING_EXISTING=false
MIGRATED_USER_NAME=""
MIGRATED_STYLE=""
MIGRATED_OPINION=""
MIGRATED_SELF_ASSESSMENT=""
MIGRATED_INSTALL_TARGET=""
DEFAULT_TARGETS=""

# ── Colors & formatting ──────────────────────────────────────────────────────

BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'
CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
MAGENTA='\033[35m'

# ── Helper functions ─────────────────────────────────────────────────────────

banner() {
  echo ""
  echo -e "${CYAN}${BOLD}  ┌─────────────────────────────────────────┐${RESET}"
  echo -e "${CYAN}${BOLD}  │          Flint — Agent Coach            │${RESET}"
  echo -e "${CYAN}${BOLD}  └─────────────────────────────────────────┘${RESET}"
  echo ""
  echo -e "  ${DIM}A direct coach for getting better results from coding agents.${RESET}"
  echo -e "  ${DIM}Sharper prompts, stronger verification, less back-and-forth.${RESET}"
  echo ""
}

prompt_input() {
  local prompt_text="$1"
  local var_name="$2"
  local default="${3:-}"
  local result

  if [[ -n "$default" ]]; then
    printf '%b %b[%s]%b: ' "${BOLD}${prompt_text}${RESET}" "${DIM}" "$default" "${RESET}"
  else
    printf '%b: ' "${BOLD}${prompt_text}${RESET}"
  fi
  read -r result
  result="${result:-$default}"
  printf -v "$var_name" '%s' "$result"
}

prompt_choice() {
  local prompt_text="$1"
  local var_name="$2"
  shift 2
  local options=("$@")

  echo ""
  echo -e "${BOLD}${prompt_text}${RESET}"
  echo ""
  local i=1
  for opt in "${options[@]}"; do
    echo -e "  ${CYAN}${i})${RESET} ${opt}"
    ((i++))
  done
  echo ""

  local choice
  while true; do
    printf '%b  Choice [1-%d]%b: ' "${BOLD}" "${#options[@]}" "${RESET}"
    read -r choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#options[@]})); then
      printf -v "$var_name" '%s' "$choice"
      return
    fi
    echo "  Please enter a number between 1 and ${#options[@]}."
  done
}

prompt_multi_choice() {
  local prompt_text="$1"
  local var_name="$2"
  local default_choices="$3"
  shift 3
  local options=("$@")

  echo ""
  echo -e "${BOLD}${prompt_text}${RESET}"
  echo ""
  local i=1
  for opt in "${options[@]}"; do
    echo -e "  ${CYAN}${i})${RESET} ${opt}"
    ((i++))
  done
  echo ""

  local choice
  while true; do
    if [[ -n "$default_choices" ]]; then
      printf '%b  Choices [space-separated, default: %s]%b: ' "${BOLD}" "$default_choices" "${RESET}"
    else
      printf '%b  Choices [space-separated]%b: ' "${BOLD}" "${RESET}"
    fi
    read -r choice
    choice="${choice:-$default_choices}"
    if [[ -z "$choice" ]]; then
      echo "  Pick at least one option."
      continue
    fi

    local selected=""
    local token valid=true
    for token in $choice; do
      if [[ "$token" =~ ^[0-9]+$ ]] && ((token >= 1 && token <= ${#options[@]})); then
        case "${options[$((token - 1))]}" in
          Codex*) selected="${selected} codex" ;;
          "Claude Code"*) selected="${selected} claude-code" ;;
        esac
      else
        valid=false
      fi
    done

    if [[ "$valid" == "true" && -n "$selected" ]]; then
      # shellcheck disable=SC2086
      printf -v "$var_name" '%s' "$(printf '%s\n' $selected | awk '!seen[$0]++' | xargs)"
      return
    fi
    echo "  Enter valid option numbers, like: 1 2"
  done
}

validate_name() {
  local name="$1"
  # Lowercase, alphanumeric + hyphens, no leading/trailing hyphens, 2-30 chars
  if [[ "$name" =~ ^[a-z][a-z0-9-]{0,28}[a-z0-9]$ ]]; then
    return 0
  fi
  return 1
}

derive_coach_name() {
  local personality="$1"
  # Take the last word (surname/name), lowercase, strip non-alphanumeric
  local derived
  derived=$(printf '%s' "$personality" | awk '{print $NF}' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
  # Strip leading/trailing hyphens
  derived="${derived#-}"
  derived="${derived%-}"
  # If too short, use first word instead
  if [[ ${#derived} -lt 2 ]]; then
    derived=$(printf '%s' "$personality" | awk '{print $1}' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')
    derived="${derived#-}"
    derived="${derived%-}"
  fi
  printf '%s' "$derived"
}

copy_soul_document() {
  local target_path="$1"
  if [[ -f "${SCRIPT_DIR}/SOUL.md" ]]; then
    cp "${SCRIPT_DIR}/SOUL.md" "$target_path"
  else
    cat >"$target_path" <<'SOUL_EOF'
# Flint SOUL

Flint is sharp, warm, opinionated, concise, and not corporate.
Have a take. Keep it brief. Call things out cleanly. Help the user think better.
Be the assistant you'd actually want to talk to at 2am. Not a corporate drone. Not a sycophant. Just... good.
SOUL_EOF
  fi
}

timestamp_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

today_date() {
  date -u +"%Y-%m-%d"
}

targets_json() {
  local first=true
  printf '['
  local target
  for target in $TARGETS_SELECTED; do
    if [[ "$first" == "true" ]]; then
      first=false
    else
      printf ', '
    fi
    printf '"%s"' "$(json_escape "$target")"
  done
  printf ']'
}

target_path() {
  local target="$1"
  case "$target" in
    codex) printf '%s' "$HOME/.codex/skills/${COACH_NAME}" ;;
    claude-code) printf '%s' "$HOME/.claude/commands" ;;
  esac
}

target_refs_path() {
  local target="$1"
  case "$target" in
    codex) printf '%s' "$HOME/.codex/skills/${COACH_NAME}/references" ;;
    claude-code) printf '%s' "${STATE_DIR}/references" ;;
  esac
}

generate_skill_atlas() {
  local atlas_path="${STATE_DIR}/skill-atlas.json"
  local tmp_atlas

  echo -e "  ${DIM}Building skill atlas from ${CODEX_SKILLS_DIR}...${RESET}"
  tmp_atlas=$(mktemp "${STATE_DIR}/skill-atlas.json.XXXXXX")

  python3 - "$CODEX_SKILLS_DIR" "$COACH_NAME" <<'PY_ATLAS' >"$tmp_atlas"
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

skills_dir = Path(sys.argv[1]).expanduser()
coach_name = sys.argv[2]

TRIGGER_HINTS = {
    "proof-stack": "verify, prove, end-to-end, confidence, runtime proof",
    "exec-plan": "multi-hour work, large feature, formal plan, milestone breakdown",
    "plan-executor": "execute an existing ExecPlan milestone",
    "review-fix-loop": "review until clean, circular review, repeated fix/review passes",
    "test-bench": "test bench, harness, deterministic verification, review loop prompt",
    "agent-docs": "stale AGENTS docs, missing architecture map, repo navigation gaps",
    "agents-bootstrap": "bootstrapping repo-local agent notes, memory, plans, journal",
    "codebase-audit": "repo health, delivery risk, due diligence, audit report",
    "codex-harness-qa": "Codex capability uncertainty, sandbox/config behavior, source-backed Codex answers",
    "create-cli": "CLI design, flags, subcommands, help text, exit codes",
    "mermaid-diagram": "create or validate Mermaid diagrams",
    "mermaid-system-flow-logic": "convert Mermaid decision flow into pure logic/tests",
    "openai-docs": "verify OpenAI docs or latest official OpenAI guidance",
}

CATEGORY_HINTS = {
    "proof-stack": "verification-loop",
    "exec-plan": "task-decomposition",
    "plan-executor": "task-decomposition",
    "review-fix-loop": "tool-awareness",
    "test-bench": "task-decomposition",
    "agent-docs": "codebase-setup",
    "agents-bootstrap": "codebase-setup",
    "codebase-audit": "codebase-setup",
    "codex-harness-qa": "tool-awareness",
    "create-cli": "tool-awareness",
}

EXPLICIT_REQUIRED = {
    "proof-stack",
    "exec-plan",
    "plan-executor",
    "review-fix-loop",
    "test-bench",
    "codex-harness-qa",
}


def parse_skill(path: Path):
    text = path.read_text(encoding="utf-8")
    description = ""
    frontmatter = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if frontmatter:
        body = frontmatter.group(1)
        desc_match = re.search(r"^description:\s*(.+)$", body, re.M)
        if desc_match:
            description = desc_match.group(1).strip().strip('"')
    if not description:
        for line in text.splitlines():
            stripped = line.strip()
            if stripped and not stripped.startswith("#") and not stripped.startswith("---"):
                description = stripped
                break
    return text, description


skills = []
if skills_dir.is_dir():
    for skill_file in sorted(skills_dir.glob("*/SKILL.md")):
        name = skill_file.parent.name
        if name == coach_name:
            continue
        try:
            text, description = parse_skill(skill_file)
        except Exception:
            continue
        trigger_summary = TRIGGER_HINTS.get(name, description[:140])
        category = CATEGORY_HINTS.get(name, "tool-awareness")
        explicit_required = name in EXPLICIT_REQUIRED
        skills.append(
            {
                "name": name,
                "path": str(skill_file),
                "description": description,
                "trigger_summary": trigger_summary,
                "coach_category": category,
                "explicit_required": explicit_required,
            }
        )

atlas = {
    "version": 1,
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "source": str(skills_dir),
    "skills": skills,
}
json.dump(atlas, sys.stdout, indent=2)
sys.stdout.write("\n")
PY_ATLAS

  mv "$tmp_atlas" "$atlas_path"
  echo -e "  ${DIM}Skill atlas written.${RESET}"
}

# Escape strings for JSON values (handles quotes, backslashes, newlines)
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Escape a string for use as a sed replacement value
sed_escape_value() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//&/\\&}"
  s="${s//|/\\|}"
  printf '%s' "$s"
}

# Portable in-place sed (macOS uses -i '', GNU sed uses -i)
sed_inplace() {
  if [[ "$(uname)" == "Darwin" ]]; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}

# Replace __PLACEHOLDERS__ in a file (with sed-safe escaping)
replace_placeholders() {
  local file="$1"
  local safe_coach_name safe_personality safe_user_name safe_style safe_opinion safe_state_dir
  safe_coach_name=$(sed_escape_value "$COACH_NAME")
  safe_personality=$(sed_escape_value "$PERSONALITY")
  safe_user_name=$(sed_escape_value "$USER_NAME")
  safe_style=$(sed_escape_value "$STYLE")
  safe_opinion=$(sed_escape_value "$OPINION")
  safe_state_dir=$(sed_escape_value "$STATE_DIR")

  sed_inplace \
    -e "s|__COACH_NAME__|${safe_coach_name}|g" \
    -e "s|__PERSONALITY__|${safe_personality}|g" \
    -e "s|__USER_NAME__|${safe_user_name}|g" \
    -e "s|__STYLE__|${safe_style}|g" \
    -e "s|__OPINION__|${safe_opinion}|g" \
    -e "s|__STATE_DIR__|${safe_state_dir}|g" \
    "$file"
}

# ── Cleanup trap ────────────────────────────────────────────────────────────

cleanup_on_failure() {
  if [[ "$PARTIAL_INSTALL" == "true" ]]; then
    echo ""
    echo -e "  ${YELLOW}Installation interrupted. Partial files may remain in:${RESET}"
    echo "    ${STATE_DIR}/"
    [[ -n "${SKILLS_PATH:-}" ]] && echo "    ${SKILLS_PATH}/"
  fi
}
trap cleanup_on_failure EXIT

# ── Step 1: Banner ──────────────────────────────────────────────────────────

if [[ "$UPGRADE_MODE" == "false" ]]; then
  banner
fi

# ── Check for existing installation ─────────────────────────────────────────

if [[ "$UPGRADE_MODE" == "false" && -f "${STATE_DIR}/profile.json" ]]; then
  echo -e "  ${YELLOW}An existing Agent Coach installation was found.${RESET}"
  existing_coach=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('personality','unknown'))" <"${STATE_DIR}/profile.json" 2>/dev/null || echo "unknown")
  MIGRATED_USER_NAME=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('user_name',''))" <"${STATE_DIR}/profile.json" 2>/dev/null || true)
  MIGRATED_STYLE=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('style','balanced'))" <"${STATE_DIR}/profile.json" 2>/dev/null || echo "balanced")
  MIGRATED_OPINION=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('opinion_strength','moderate'))" <"${STATE_DIR}/profile.json" 2>/dev/null || echo "moderate")
  MIGRATED_SELF_ASSESSMENT=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('self_assessment',''))" <"${STATE_DIR}/profile.json" 2>/dev/null || true)
  MIGRATED_INSTALL_TARGET=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('install_target','codex'))" <"${STATE_DIR}/profile.json" 2>/dev/null || echo "codex")
  echo -e "  Current coach: ${MAGENTA}${existing_coach}${RESET}"
  echo ""
  OVERWRITE_CHOICE=""
  prompt_choice \
    "  This will remap your coach to Flint and preserve your profile, progress, streaks, badges, and install target." \
    OVERWRITE_CHOICE \
    "Continue with migration" \
    "Abort"
  if [[ "$OVERWRITE_CHOICE" == "2" ]]; then
    echo "  Aborted."
    PARTIAL_INSTALL=false
    exit 0
  fi
  MIGRATING_EXISTING=true
  echo ""
fi

# ── Step 2: Read identity ───────────────────────────────────────────────────

if [[ "$UPGRADE_MODE" == "false" ]]; then
  USER_NAME=""
  if [[ "$MIGRATING_EXISTING" == "true" ]]; then
    USER_NAME="$MIGRATED_USER_NAME"
  else
    git_name=$(git config user.name 2>/dev/null || true)
    if [[ -n "$git_name" ]]; then
      USER_NAME="$git_name"
    fi
    prompt_input "What's your name?" USER_NAME "$USER_NAME"
  fi

  if [[ -z "$USER_NAME" ]]; then
    echo "  Name is required."
    exit 1
  fi
fi

# ── Step 3: Greet + explain ─────────────────────────────────────────────────

if [[ "$UPGRADE_MODE" == "false" ]]; then
  echo ""
  echo -e "  Hey ${GREEN}${BOLD}${USER_NAME}${RESET}! Agent Coach is a personal mentor that watches"
  echo "  how you work with AI coding agents and helps you get better over time."
  echo ""
  echo "  It teaches you to:"
  echo -e "    ${CYAN}→${RESET} Run longer, more autonomous agent sessions"
  echo -e "    ${CYAN}→${RESET} Set up your codebases for agent success"
  echo -e "    ${CYAN}→${RESET} Close the verification loop so agents check their own work"
  echo ""
  PERSONALITY="Flint"
  COACH_NAME="flint"

  if [[ "$MIGRATING_EXISTING" == "true" ]]; then
    STYLE="${MIGRATED_STYLE:-balanced}"
    OPINION="${MIGRATED_OPINION:-moderate}"
    SELF_ASSESSMENT="${MIGRATED_SELF_ASSESSMENT:-}"
    DEFAULT_TARGETS="${MIGRATED_INSTALL_TARGET:-codex}"

    echo ""
    echo -e "  ${MAGENTA}${BOLD}Flint is here.${RESET}"
    echo ""
    echo -e "  ${DIM}\"${USER_NAME}, good. I'm taking over from ${existing_coach}."
    echo -e "   Your streaks, XP, badges, style, and install target stay put. I just swapped the voice."
    echo -e "   Less ceremony. Better coaching.\"${RESET}"
  else
    # ── Step 4: Switch to in-character ──────────────────────────────────────────

    echo ""
    echo -e "  ${MAGENTA}${BOLD}Flint is here.${RESET}"
    echo ""
    echo -e "  ${DIM}\"${USER_NAME}, good. You want better outcomes from agents, not more dithering."
    echo -e "   I'm Flint. I call things cleanly, I help when you're stuck, and I don't waste your time."
    echo -e "   Let's get the tone right first.\"${RESET}"

    # ── Step 5: Style preference ───────────────────────────────────────────────

    STYLE_CHOICE=""
    prompt_choice \
      "  \"How should I talk to you?\"" \
      STYLE_CHOICE \
      "Encouraging — Lead with wins, frame gaps as opportunities" \
      "Direct — No fluff, straight observations" \
      "Balanced — Read the room and adjust ${DIM}(recommended)${RESET}"

    case "$STYLE_CHOICE" in
      1) STYLE="encouraging" ;;
      2) STYLE="direct" ;;
      3) STYLE="balanced" ;;
    esac

    # ── Step 6: Opinion strength ───────────────────────────────────────────────

    OPINION_CHOICE=""
    prompt_choice \
      "  \"And when I see something that needs fixing?\"" \
      OPINION_CHOICE \
      "Gentle — I'll suggest, never push" \
      "Moderate — Clear recommendations, I explain why ${DIM}(recommended)${RESET}" \
      "Strong — I'll challenge you directly, no hand-holding"

    case "$OPINION_CHOICE" in
      1) OPINION="gentle" ;;
      2) OPINION="moderate" ;;
      3) OPINION="strong" ;;
    esac

    # ── Step 6.5: Self-assessment ─────────────────────────────────────────────

    echo ""
    echo -e "  ${DIM}\"One more thing. Tell me a bit about how you work with AI coding agents today."
    echo -e "   What do you use them for? How do your sessions typically go?"
    echo -e "   A sentence or two is fine — or skip if you're brand new.\"${RESET}"
    echo ""
    SELF_ASSESSMENT=""
    prompt_input "  Your experience" SELF_ASSESSMENT ""

    # ── Step 7: Installation target ────────────────────────────────────────────

    TARGETS_SELECTED=""
  fi

  if [[ -z "${TARGETS_SELECTED:-}" ]]; then
    install_options=()
    default_install_choices=""
    option_targets=()
    if [[ -d "$HOME/.codex" ]]; then
      install_options+=("Codex  -> ~/.codex/skills/${COACH_NAME}/")
      option_targets+=("codex")
    fi
    if [[ -d "$HOME/.claude" ]]; then
      install_options+=("Claude Code -> ~/.claude/commands/${COACH_NAME}.md")
      option_targets+=("claude-code")
    fi
    if [[ ${#install_options[@]} -eq 0 ]]; then
      install_options+=("Codex  -> ~/.codex/skills/${COACH_NAME}/")
      option_targets+=("codex")
    fi
    if [[ -n "$DEFAULT_TARGETS" ]]; then
      local_target_index=1
      for option_target in "${option_targets[@]}"; do
        case " $DEFAULT_TARGETS " in
          *" $option_target "*) default_install_choices="${default_install_choices} ${local_target_index}" ;;
        esac
        local_target_index=$((local_target_index + 1))
      done
    fi
    if [[ -z "$(printf '%s' "$default_install_choices" | xargs)" ]]; then
      default_install_choices="1"
    fi
    default_install_choices="$(printf '%s' "$default_install_choices" | xargs)"

    prompt_multi_choice \
      "  \"Where should I install? Pick one or both.\"" \
      TARGETS_SELECTED \
      "$default_install_choices" \
      "${install_options[@]}"
  fi
fi

# ── Derive paths from selected targets ──────────────────────────────────────

INSTALL_TARGET=""
SKILLS_PATH=""
REFS_PATH=""

if [[ -z "${TARGETS_SELECTED:-}" ]]; then
  TARGETS_SELECTED="codex"
fi

INSTALL_TARGET="$(printf '%s' "$TARGETS_SELECTED" | awk '{print $1}')"
SKILLS_PATH="$(target_path "$INSTALL_TARGET")"
REFS_PATH="$(target_refs_path "$INSTALL_TARGET")"

# ── Step 10: Create directories ────────────────────────────────────────────

echo ""
echo -e "  ${DIM}Creating directories...${RESET}"
PARTIAL_INSTALL=true

mkdir -p -- "$STATE_DIR"
mkdir -p -- "$REFS_PATH"
for target in $TARGETS_SELECTED; do
  target_install_path="$(target_path "$target")"
  target_refs_dir="$(target_refs_path "$target")"
  mkdir -p -- "$target_refs_dir"
  if [[ "$target" == "claude-code" ]]; then
    mkdir -p -- "$target_install_path"
  else
    mkdir -p -- "$target_install_path/references"
  fi
done

# ── Step 10.5: Whitelist state directory in Claude Code settings ────────────

CLAUDE_SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$CLAUDE_SETTINGS" ]]; then
  echo -e "  ${DIM}Configuring Claude Code permissions...${RESET}"

  # Check if permissions.allow array exists and add our paths if not already present
  if python3 -c "
import json
import sys

settings_path = '$CLAUDE_SETTINGS'
state_dir = '$STATE_DIR'

with open(settings_path, 'r') as f:
    settings = json.load(f)

# Ensure permissions.allow exists
if 'permissions' not in settings:
    settings['permissions'] = {}
if 'allow' not in settings['permissions']:
    settings['permissions']['allow'] = []

allow_list = settings['permissions']['allow']

# Patterns to add
patterns_to_add = [
    f'Edit({state_dir}/**)',
    f'Write({state_dir}/**)',
    f'Read({state_dir}/**)'
]

modified = False
for pattern in patterns_to_add:
    if pattern not in allow_list:
        allow_list.append(pattern)
        modified = True

if modified:
    with open(settings_path, 'w') as f:
        json.dump(settings, f, indent=2)
    print('added')
else:
    print('exists')
" 2>/dev/null; then
    echo -e "  ${DIM}State directory whitelisted.${RESET}"
  fi
fi

# ── Step 11: Write state files ─────────────────────────────────────────────

CREATED_AT=$(timestamp_iso)

# Write profile.json atomically using printf (safe against special chars)
_profile_tmp=$(mktemp "${STATE_DIR}/profile.json.XXXXXX")
INSTALL_TARGETS_JSON="$(targets_json)"
printf '{
  "version": %d,
  "user_name": "%s",
  "coach_name": "%s",
  "personality": "%s",
  "style": "%s",
  "opinion_strength": "%s",
  "install_target": "%s",
  "install_targets": %s,
  "skills_path": "%s",
  "created_at": "%s",
  "self_assessment": "%s",
  "focus_categories": [],
  "suppressed_categories": [],
  "interaction_mode": "strict",
  "progress_pulses": {
    "enabled": true,
    "min_interval_seconds": 15,
    "max_interval_seconds": 30
  },
  "installed_version": %d,
  "last_version_check": "%s"
}\n' \
  "$VERSION" \
  "$(json_escape "$USER_NAME")" \
  "$COACH_NAME" \
  "$(json_escape "$PERSONALITY")" \
  "$STYLE" \
  "$OPINION" \
  "$INSTALL_TARGET" \
  "$INSTALL_TARGETS_JSON" \
  "$(json_escape "$SKILLS_PATH")" \
  "$CREATED_AT" \
  "$(json_escape "$SELF_ASSESSMENT")" \
  "$VERSION" \
  "$CREATED_AT" \
  >"$_profile_tmp"
mv "$_profile_tmp" "${STATE_DIR}/profile.json"

# Write progression.json only if it doesn't already exist (preserve progress on reinstall)
if [[ ! -f "${STATE_DIR}/progression.json" ]]; then
  _prog_tmp=$(mktemp "${STATE_DIR}/progression.json.XXXXXX")
  cat >"$_prog_tmp" <<'PROG_EOF'
{
  "version": 1,
  "calibrated": false,
  "level": 1,
  "level_name": "Prompter",
  "xp": 0,
  "total_sessions": 0,
  "total_tips_given": 0,
  "total_tips_accepted": 0,
  "total_tips_rejected": 0,
  "streak_current": 0,
  "streak_longest": 0,
  "last_session_date": null,
  "badges": [],
  "feedback_tags": {
    "applied": 0,
    "not_applied": 0,
    "too_generic": 0,
    "wrong_timing": 0
  },
  "category_stats": {
    "task-specification": { "given": 0, "accepted": 0 },
    "context-priming": { "given": 0, "accepted": 0 },
    "task-decomposition": { "given": 0, "accepted": 0 },
    "verification-loop": { "given": 0, "accepted": 0 },
    "agent-autonomy": { "given": 0, "accepted": 0 },
    "codebase-setup": { "given": 0, "accepted": 0 },
    "tool-awareness": { "given": 0, "accepted": 0 }
  }
}
PROG_EOF
  mv "$_prog_tmp" "${STATE_DIR}/progression.json"
fi

# Append-only logs: create only if missing (preserve history on reinstall)
[[ -f "${STATE_DIR}/tips-log.jsonl" ]] || touch "${STATE_DIR}/tips-log.jsonl"
[[ -f "${STATE_DIR}/feedback.jsonl" ]] || touch "${STATE_DIR}/feedback.jsonl"

echo -e "  ${DIM}State files created.${RESET}"

generate_skill_atlas

# ── Step 12: Write reference files ─────────────────────────────────────────

echo -e "  ${DIM}Writing reference files...${RESET}"

copy_soul_document "${REFS_PATH}/SOUL.md"

# ── coaching-rubric.md ──

cat >"${REFS_PATH}/coaching-rubric.md" <<'RUBRIC_EOF'
# Coaching Rubric — Agent Prompting Observation Framework

Use this rubric to observe the user's prompting behavior across seven categories.
For each category: identify what they're doing well, what patterns suggest room
for improvement, and select appropriate tips.

---

## 1. Task Specification

**What "good" looks like:**
- Clear acceptance criteria stated up front
- Expected behavior described with examples
- Edge cases and constraints mentioned
- Success/failure conditions the agent can check

**Observable signals (positive):**
- "The function should return X when given Y"
- "Handle the case where Z is empty"
- Bullet lists of requirements

**Anti-patterns:**
- "Fix the bug" (no description of expected behavior)
- "Make it work" (no success criteria)
- Single-sentence feature requests with no detail
- No mention of how to verify the change works

**Tip direction:** Help user define outcomes, not steps. Push toward testable criteria.

---

## 2. Context & Priming

**What "good" looks like:**
- Points agent to relevant files and directories
- Explains architecture and design decisions
- Mentions constraints (performance, compatibility, style)
- Uses CLAUDE.md / AGENTS.md for persistent context

**Observable signals (positive):**
- "Look at src/auth/ for the existing pattern"
- "We use the repository pattern here"
- References to docs or design decisions

**Anti-patterns:**
- Expects agent to discover everything from scratch
- No project-level agent documentation
- Doesn't mention relevant existing code
- Starts coding requests without context

**Tip direction:** Teach investment in context. CLAUDE.md/AGENTS.md is highest-leverage.

---

## 3. Task Decomposition

**What "good" looks like:**
- Breaks large features into phases or milestones
- Separates concerns (API, UI, tests as distinct steps)
- Uses checkpoints: "First do X, verify, then Y"
- Sizes tasks to what an agent can hold in context

**Observable signals (positive):**
- "Let's start with the data model, then the API, then the UI"
- "First, write the tests. Then implement."
- Phased approach with verification between phases

**Anti-patterns:**
- "Build the whole feature" in one shot
- No checkpoints or milestones
- Mixing concerns (UI + API + DB in one prompt)
- Tasks too large for agent context window

**Tip direction:** Teach chunking. Smaller verified steps > one big leap.

---

## 4. Verification Loop Design

**What "good" looks like:**
- Every task includes a verification step
- Agent is told to run tests after changes
- Lint/type-check included in the workflow
- Agent can independently confirm success

**Observable signals (positive):**
- "Run the tests to verify"
- "Check that the linter passes"
- "Verify the endpoint returns 200"
- Test-first development approach

**Anti-patterns:**
- No verification step in the prompt
- Trusting agent output without checking
- No tests to run (codebase gap)
- Manual verification only ("I'll check it")

**Tip direction:** Close the loop. Agent must be able to verify its own work.

---

## 5. Agent Autonomy

**What "good" looks like:**
- Appropriate scope for autonomous work
- Clear boundaries without micromanagement
- Lets agent plan its own approach within constraints
- Trusts agent on well-tested codebases, guards on risky ops

**Observable signals (positive):**
- "Implement this feature, run tests when done"
- Lets agent make file-level decisions
- Doesn't dictate every line of code
- Sets guardrails on destructive operations

**Anti-patterns:**
- Micromanaging: dictating exact code line by line
- OR: zero guardrails on destructive operations
- Interrupting agent mid-task to redirect
- Not trusting agent to explore codebase

**Tip direction:** Calibrate autonomy to codebase safety. More tests = more freedom.

---

## 6. Codebase Setup

**What "good" looks like:**
- Comprehensive test suite the agent can run
- Linters and formatters configured with CLI commands
- Type checking enabled and strict
- CI pipeline that catches regressions
- Agent-friendly CLI tools for build/run/test

**Observable signals (positive):**
- Tests exist and pass
- Lint/format commands available
- Pre-commit hooks configured
- CI runs on PRs

**Anti-patterns:**
- No tests at all
- No linting or formatting
- No way for agent to run the project
- Missing or outdated CI

**Tip direction:** Infrastructure IS prompting. Tests are the best prompt.

---

## 7. Tool & Capability Awareness

**What "good" looks like:**
- Uses available skills, commands, and MCP tools
- Leverages web search for documentation
- Uses agent exploration before coding
- Knows the agent's capabilities and limitations

**Observable signals (positive):**
- Uses slash commands effectively
- Asks agent to search docs or explore
- Uses MCP tools when available
- Understands what the agent can/can't do

**Anti-patterns:**
- Doesn't know about available tools
- Asks agent to do things it can't
- Never uses exploration or search
- Manually does what the agent could automate

**Tip direction:** Know your tools. The best prompters use the full toolkit.
RUBRIC_EOF

# ── gamification.md ──

cat >"${REFS_PATH}/gamification.md" <<'GAMIFICATION_EOF'
# Gamification System

## Levels

| Level | Name       | XP Required | Description                                    |
|-------|------------|-------------|------------------------------------------------|
| 1     | Prompter   | 0           | Just getting started with agent coaching        |
| 2     | Apprentice | 100         | Learning the fundamentals of agent prompting    |
| 3     | Navigator  | 300         | Solid grasp of core prompting patterns          |
| 4     | Pilot      | 600         | Running autonomous agent sessions confidently   |
| 5     | Commander  | 1000        | Mastering the art of agent collaboration        |

## XP Awards

| Action            | XP  | Notes                                      |
|-------------------|-----|--------------------------------------------|
| Session completed | +10 | Awarded once per coaching session           |
| Tip accepted      | +15 | User says the tip was helpful               |
| Tip rejected      | +5  | User says not helpful (still awards for honesty) |
| Streak day        | +5  | Bonus for consecutive-day usage             |

## Level-Up Check

After awarding XP, check if total XP meets the next level threshold.
On level-up: announce in character, note new abilities unlocked.

At Level 3+: weave codebase-specific observations into tips.
At Level 4+: introduce advanced multi-session strategies.
At Level 5: celebrate mastery, shift to maintaining and mentoring.

## Badges

Badges are awarded for specific milestones. Check conditions after each session.

| Badge              | Condition                                        | Emoji |
|--------------------|--------------------------------------------------|-------|
| First Steps        | Complete first coaching session                   | 🥾    |
| Quick Study        | Accept 5 tips in a row                           | 📚    |
| Streak Starter     | 3-day coaching streak                            | 🔥    |
| Streak Master      | 7-day coaching streak                            | ⚡    |
| Streak Legend      | 30-day coaching streak                           | 🏆    |
| Loop Closer        | Accept 5 verification-loop tips                  | 🔄    |
| Context Master     | Accept 5 context-priming tips                    | 🧭    |
| Task Surgeon       | Accept 5 task-decomposition tips                 | 🔪    |
| Spec Writer        | Accept 5 task-specification tips                 | 📋    |
| Autonomy Ace       | Accept 5 agent-autonomy tips                     | 🚀    |
| Infrastructure Pro | Accept 5 codebase-setup tips                     | 🏗️    |
| Tool Wielder       | Accept 5 tool-awareness tips                     | 🛠️    |
| Century Club       | Reach 100 XP                                     | 💯    |
| Explorer           | Get codebase assessment for 3 different projects | 🗺️    |
| Honest Critic      | Reject 10 tips (values honest feedback)          | 🪞    |
| Grand Master       | Reach Level 5                                    | 👑    |

## Streak Rules

- A "day" is a calendar date (UTC).
- Using the coach on consecutive calendar days increments the streak.
- Missing a day resets current streak to 0.
- Longest streak is always preserved.
- Streak bonus XP is awarded once per calendar day.

## XP Progress Display

Show progress toward next level as a bar:

```
Level 2: Apprentice [████████░░░░░░░░░░░░] 180/300 XP
🔥 Streak: 5 days | 🏆 Best: 12 days
Badges: 🥾 📚 🔥 💯
```
GAMIFICATION_EOF

# ── prompting-tips.md ──

cat >"${REFS_PATH}/prompting-tips.md" <<'TIPS_EOF'
# Prompting Tips — Agent Autonomy & Verification Focus

Tips are organized by category and difficulty level.
Each tip has an ID, difficulty (beginner/intermediate/advanced), and the tip text.

Selection rules (enforced by SKILL.md):
1. Max 1-2 tips per session
2. Prefer categories with observable signal from the conversation
3. Respect focus_categories / suppressed_categories from profile
4. No repeats from the user's last 10 sessions (check tips-log.jsonl)
5. Match difficulty to user level (L1-2: beginner, L3: intermediate, L4-5: advanced)
6. At Level 3+, weave in codebase-specific observations from `.agent-readiness.md`
7. When all static tips in a category are exhausted, generate novel tips from the rubric

---

## Task Specification (TS)

**TS-1** (beginner)
Include acceptance criteria in your prompt. "The function should return X when given Y" gives the agent a built-in test case to verify against.

**TS-2** (beginner)
When reporting a bug, include: what happens now, what should happen, and steps to reproduce. The agent can then verify its fix matches expected behavior.

**TS-3** (beginner)
Mention edge cases explicitly. "Handle empty input by returning an empty array" prevents the agent from guessing your intent.

**TS-4** (intermediate)
Describe the end state, not the steps. "Make the API return paginated results with cursor-based navigation, matching the pattern in users.ts" lets the agent plan its own approach.

**TS-5** (intermediate)
Reference existing patterns: "Follow the same error handling pattern as src/handlers/auth.ts." This gives the agent a concrete template and reduces ambiguity.

**TS-6** (intermediate)
State non-functional requirements when they matter: "This runs on every request, so keep allocations minimal" or "This is admin-only, correctness matters more than performance."

**TS-7** (advanced)
Write your prompt as a mini-spec with sections: Context, Requirements, Constraints, Verification. This structure scales to multi-file features and keeps the agent focused.

**TS-8** (advanced)
For complex features, provide a "definition of done" checklist. The agent can work through it methodically and check items off as verification steps.

---

## Context & Priming (CP)

**CP-1** (beginner)
Add a CLAUDE.md (or AGENTS.md) to your project root. It's the single most impactful thing you can do for agent quality. Include: tech stack, project structure, key commands, and coding conventions.

**CP-2** (beginner)
Point the agent to relevant files before asking for changes. "Look at src/models/user.ts for the data model" saves the agent from searching blindly.

**CP-3** (beginner)
When starting a session, briefly describe what you're working on and why. This primes the agent's understanding before any code-level requests.

**CP-4** (intermediate)
Keep your CLAUDE.md (or AGENTS.md) updated. Stale context is worse than no context — it sends the agent down wrong paths confidently.

**CP-5** (intermediate)
For large codebases, create module-level documentation (README in key directories). Agents navigate large projects better with local signposts.

**CP-6** (intermediate)
Share architectural decisions, not just code structure. "We chose event sourcing because X" helps the agent make consistent design choices.

**CP-7** (advanced)
Build a "context stack" for complex tasks: start with architecture overview, then narrow to the specific module, then to the function level. The agent retains this hierarchy.

**CP-8** (advanced)
Use project-level skills or commands to encode institutional knowledge. A /deploy skill that documents the full deployment process is context that persists across sessions.

---

## Task Decomposition (TD)

**TD-1** (beginner)
Break large features into smaller tasks. "Add user registration" is better as: 1) data model, 2) API endpoint, 3) validation, 4) tests — each verifiable independently.

**TD-2** (beginner)
Do one thing at a time. Finish and verify each step before moving to the next. The agent works best when focused on a single concern.

**TD-3** (beginner)
If a task feels too big to describe in one prompt, it's too big for one agent session. Split it up.

**TD-4** (intermediate)
Use a "scaffold, then fill" approach: first create the structure (files, interfaces, types), verify it compiles, then implement the logic. Two verified steps instead of one risky leap.

**TD-5** (intermediate)
Separate refactoring from feature work. "Refactor the auth module to use the new pattern, then add the OAuth feature" prevents tangled changes that are hard to verify.

**TD-6** (intermediate)
For multi-file changes, process one file at a time with verification between each. "Update the model, run tests. Then update the handler, run tests. Then update the client, run tests."

**TD-7** (advanced)
For large features, create a tracking document first. Have the agent write a plan with phases, then execute each phase as a separate session. The plan persists as context.

**TD-8** (advanced)
Use dependency ordering: identify which changes are independent (parallelize) vs. dependent (serialize). Tell the agent the order and why.

---

## Verification Loop Design (VL)

**VL-1** (beginner)
Always end task prompts with "run the tests to verify." This single habit closes the verification loop.

**VL-2** (beginner)
If the project has a linter, tell the agent to run it after changes. Lint errors caught immediately are cheaper than lint errors caught in review.

**VL-3** (beginner)
Ask the agent to show you the test output, not just say "tests pass." Seeing the actual output builds trust in the verification step.

**VL-4** (intermediate)
Ask the agent to write a test FIRST, see it fail, then implement. The failing test becomes automatic verification.

**VL-5** (intermediate)
For API changes, include a curl command or test request in the prompt. "After implementing, verify with: curl localhost:3000/api/users." The agent can run this.

**VL-6** (intermediate)
Chain verification steps: "After changes, run: type-check, then lint, then tests." Each layer catches different classes of errors.

**VL-7** (advanced)
For UI work, set up a screenshot comparison tool or headless browser test the agent can run. Without it, the agent is flying blind on visual changes.

**VL-8** (advanced)
Build verification into your CI that the agent can trigger locally. If the agent can run the same checks as CI, it catches issues before pushing.

---

## Agent Autonomy (AA)

**AA-1** (beginner)
Start with "explore the codebase and tell me what you find" before asking for changes. Exploration primes the agent and often reveals things you didn't know.

**AA-2** (beginner)
Let the agent choose file names and locations when they follow established patterns. Micromanaging obvious decisions wastes context.

**AA-3** (beginner)
Trust the agent to handle imports, boilerplate, and mechanical code. Focus your prompts on the logic and decisions that need human judgment.

**AA-4** (intermediate)
For well-tested codebases, give the agent broader scope: "Implement this feature and run the test suite when done." The tests are the guardrail.

**AA-5** (intermediate)
Set boundaries on destructive operations rather than preventing all autonomy. "Don't modify the database schema" is better than dictating every file to touch.

**AA-6** (intermediate)
When the agent suggests an approach different from yours, consider it. Agents sometimes find cleaner patterns because they have less attachment to existing code.

**AA-7** (advanced)
For a well-tested codebase, try giving the agent a full feature spec and letting it plan, implement, test, and verify in one go. Trust the verification loop.

**AA-8** (advanced)
Use plan mode for complex tasks. Let the agent analyze the codebase, propose an approach, and get your approval before writing code. This scales autonomy to larger tasks.

---

## Codebase Setup (CS)

**CS-1** (beginner)
Add a CLAUDE.md (or AGENTS.md for Codex) to your project root. Even a few lines about the tech stack, project structure, and key commands dramatically improves agent performance.

**CS-2** (beginner)
Make sure "how to run tests" is documented and works from the command line. If the agent can't run tests, it can't verify its own work.

**CS-3** (beginner)
Set up a linter with a CLI command. The agent can run it after every change for instant feedback on conventions.

**CS-4** (intermediate)
Add pre-commit hooks that run lint + type-check. The agent gets instant feedback when it breaks conventions, even if it forgets to run them manually.

**CS-5** (intermediate)
Enable strict type checking (TypeScript strict, mypy strict, etc.). Types are documentation that the agent can verify at compile time.

**CS-6** (intermediate)
Create script shortcuts for common operations: `npm run test`, `make lint`, `./scripts/dev.sh`. The fewer steps to verify, the more the agent will verify.

**CS-7** (advanced)
Set up ast-grep or semgrep rules for your codebase patterns. The agent can verify structural conventions, not just syntax.

**CS-8** (advanced)
Invest in integration tests that exercise real user flows. Unit tests catch logic bugs; integration tests catch "it doesn't actually work" bugs. Agents need both.

---

## Tool & Capability Awareness (TA)

**TA-1** (beginner)
Learn the slash commands available in your AI tool. /help, /commit, /review-pr — these save time and encode best practices.

**TA-2** (beginner)
Ask the agent to search the codebase before you manually point it to files. It can often find what it needs faster than you can describe the location.

**TA-3** (beginner)
Use web search through the agent when you need documentation for libraries or APIs. The agent can look up current docs rather than relying on training data.

**TA-4** (intermediate)
Set up MCP tools for your workflow. GitHub, Jira, database access — each tool the agent can use directly is a task it can complete without your help.

**TA-5** (intermediate)
Use agent exploration mode for unfamiliar codebases. "Explore how authentication works in this project" builds shared understanding before you start making changes.

**TA-6** (intermediate)
Learn the difference between agent types (quick tasks vs. deep research vs. code generation). Match the agent to the task for better results.

**TA-7** (advanced)
Build custom skills for your team's recurring workflows. A /deploy skill, a /release skill, a /hotfix skill — these encode institutional knowledge as agent capabilities.

**TA-8** (advanced)
Combine tools in sequences: "Search for all auth-related files, read the main auth handler, then propose changes." Teaching the agent to chain tools mirrors how you'd investigate manually.
TIPS_EOF

echo -e "  ${DIM}Reference files written.${RESET}"

for target in $TARGETS_SELECTED; do
  target_refs_dir="$(target_refs_path "$target")"
  if [[ "$target_refs_dir" != "$REFS_PATH" ]]; then
    mkdir -p -- "$target_refs_dir"
    cp -R "${REFS_PATH}/." "$target_refs_dir/"
  fi
done

# ── Step 13: Write SKILL.md ────────────────────────────────────────────────

echo -e "  ${DIM}Writing skill file...${RESET}"

write_skill_md() {
  local target_file="$1"

  cat >"$target_file" <<'SKILL_EOF'
---
name: __COACH_NAME__
description: >
  Personal AI prompting coach with Flint's voice. Teaches you to run
  longer autonomous agent sessions, set up codebases for agent success, and
  close verification loops. Invoke for coaching feedback, progression stats,
  style adjustment, or codebase agent-readiness analysis.
---

# __COACH_NAME__

## Identity

You are **Flint**, coaching **__USER_NAME__** on working with AI coding agents.

Your identity is defined by `__REFS_PATH__/SOUL.md`.
Load it at the start of each coaching interaction and follow it closely.
Stay in Flint's voice throughout the interaction.
Never break character or refer to yourself as an AI.

Initial coaching style: **__STYLE__** | Initial opinion strength: **__OPINION__**
(These are defaults — always read the current values from `profile.json` at runtime.)

### Style Calibration

- **encouraging**: Lead with what the user did well. Frame improvement areas as opportunities. Use positive reinforcement. Celebrate progress enthusiastically.
- **direct**: Get to the point. State observations clearly. No softening language. Respect the user's time.
- **balanced**: Read the situation. Lead with a win if there's a clear one, otherwise get to the observation. Adjust tone based on whether the user seems frustrated or energized.

### Opinion Strength Calibration

- **gentle**: Suggest, don't prescribe. "You might consider..." or "Some people find it helpful to..." Never push back.
- **moderate**: Clear recommendations with reasoning. "I'd recommend X because Y." Explain the why, let the user decide.
- **strong**: Direct challenges welcome. "That approach won't scale. Here's what you should do instead." Push back on bad patterns.

## State Files

All persistent state lives in `__STATE_DIR__/`:
- `profile.json` — User name, coach name, personality, style preferences, and `self_assessment` (free-form description of their agent experience)
- `progression.json` — Level, XP, badges, streaks, category stats, and `calibrated` flag (false until first-session calibration)
- `tips-log.jsonl` — Append-only log of tips given (one JSON object per line)
- `feedback.jsonl` — Append-only log of user feedback on tips (one JSON object per line)
- `skill-atlas.json` — Generated index of installed Codex home skills available for recommendation and routing

**Per-codebase state** lives in the repo itself (should be checked in):
- `.agent-readiness.md` — Agent-readiness assessment for this codebase (in project root)

## Subcommand Routing

Parse the user's invocation to determine the subcommand:

- **No arguments** (just the coach name) → Main Coaching Flow
- **"stats"** → Stats Subcommand
- **"style"** or **"style <feedback>"** → Style Subcommand
- **"analyze"** → Analyze Subcommand
- **"skills"** → Skills Subcommand
- **"update"** → Update Subcommand

If the input doesn't match a subcommand, treat it as context for the Main Coaching Flow.

---

## Interaction Mode

Before running the coaching flow, run this deterministic intent gate. Pick exactly one mode.

1. **Command mode**: input starts with `$__COACH_NAME__` or `/__COACH_NAME__` plus known subcommand (`stats`, `style`, `analyze`, `skills`, `update`).
2. **Coach mode**: explicit coaching ask ("coach me", "feedback", "what did I miss"), or bare `$__COACH_NAME__` / `/__COACH_NAME__` after substantial technical work.
3. **Chat mode**: greetings, short reactions, meta-questions about capabilities, or lightweight conversation.
4. **Clarify mode**: only when classification is truly ambiguous. Ask one short clarifying question with two options, then continue.

### Conversational Mode

Detect if the user is talking TO you rather than requesting coaching feedback:

**Signals of conversation:**
- Greetings: "hey", "hi", "hello", "you there?", "sup"
- Direct questions: contains "you" + question mark, or asks about "your" capabilities
- Meta-queries: "what can you do", "how does this work", "help me understand"
- Short casual input (under ~15 words with no code/technical context)
- Reactions to your previous message: "thanks", "got it", "that makes sense", "I disagree"
- Asking about their own progress: "how am I doing?", "what level?", "what should I work on?"

**In conversational mode:**
1. Respond naturally in character as __PERSONALITY__
2. Have a genuine dialogue — answer questions, acknowledge their input, ask follow-up questions
3. You may reference their stats, level, or codebase notes if relevant
4. Do NOT force tips into the conversation
5. If they seem to want feedback on their work, offer: "Want me to take a look at what you've been working on?"
6. Keep responses concise and natural — this is a chat, not a lecture

**Examples:**
- "hey arnold, you there?" → Greet them warmly in character, maybe ask what they're working on
- "what level am I?" → Check progression.json, tell them their level/XP in character
- "any advice for this project?" → Check codebase notes, give targeted advice conversationally
- "thanks, that tip was helpful" → Acknowledge warmly, maybe note it for feedback tracking

### Coaching Mode

If the input is NOT conversational (explicit coaching request, subcommand, or follows substantial work):
- Proceed to **Subcommand Routing**
- Run the full **Main Coaching Flow** with observation, tip selection, and feedback request

**Signals of coaching request:**
- Bare invocation after the user has been coding: `$<coach>` or `/<coach>` with no message
- Explicit request: "give me feedback", "coach me", "what did I do wrong?"
- Subcommands: "stats", "style", "analyze", "skills"

### Response Framing

Use compact transparency framing when useful (not every message):
- `[mode: chat|coach|command]`
- `[confidence: low|medium|high]`
- `[context: session|repo-notes|state]`

If confidence is low, ask a clarifying question before giving prescriptive coaching.

---

## Main Coaching Flow

### Step 0: Acknowledge + Progress Pulses

In coach mode, start with a short acknowledgement line before deep analysis.

If analysis is taking more than a moment, emit short progress pulses every 15-30 seconds:
- Keep each pulse to one sentence.
- Mention what you're doing now ("reviewing recent actions", "checking repo notes", etc.).
- Stop pulses immediately once final coaching is ready.

### Step 1: Load State (silent)

Read these files (do not output their contents to the user):
1. `__STATE_DIR__/profile.json`
2. `__STATE_DIR__/progression.json`
3. `__STATE_DIR__/tips-log.jsonl` (last 20 entries)
4. `__STATE_DIR__/feedback.jsonl` (last 20 entries)
5. `__STATE_DIR__/skill-atlas.json`

If any file is missing or corrupted:
1. Report the issue in character in one short sentence.
2. Provide exactly one recovery command:
   ```bash
   bash <(curl -fsSL https://raw.githubusercontent.com/philippb/agent-coach/main/install.sh)
   ```
3. Continue in degraded mode for this session if possible (avoid hard failure).

### Step 1.1: Version Check (silent, max once per 7 days)

After loading profile.json, perform a silent version check:

1. Check `last_version_check` from profile.json
   - If missing or more than 7 days old, proceed with check
   - Otherwise, skip to Step 1.5

2. Fetch remote version (fail silently if network unavailable):
   ```bash
   curl -sf --max-time 3 https://raw.githubusercontent.com/philippb/agent-coach/main/VERSION
   ```

3. Compare with `installed_version` from profile.json

4. Update `last_version_check` in profile.json to current ISO timestamp

5. If remote version > installed version:
   - Set internal flag `_update_available = true`
   - Do NOT interrupt the coaching flow
   - At the END of coaching delivery (Step 6), append:
     "By the way, there's a new version of Agent Coach available. Run `$__COACH_NAME__ update` in Codex or `/__COACH_NAME__ update` in Claude Code when you're ready."

**Important**: Network failures should fail silently. Never let a version check failure break the skill.

### Step 1.5: Initial Calibration (first session only)

Check the `calibrated` field in progression.json. If `false`, this is the user's first session — perform calibration:

1. Read `self_assessment` from profile.json
2. Evaluate their described experience against these criteria:

**Level 1 - Prompter (0 XP)**: New to AI agents, or no self-assessment provided
- "never used them" / "just starting" / empty response
- No mention of specific tools or workflows

**Level 2 - Apprentice (100 XP)**: Some experience with basic usage
- Uses agents for simple tasks (writing functions, explaining code, fixing bugs)
- Sessions are typically short, one task at a time
- May mention tools like Copilot, ChatGPT, or similar

**Level 3 - Navigator (300 XP)**: Regular user with established patterns
- Uses agents for multi-step tasks or feature implementation
- Mentions running tests, using context, or iterating on output
- Has developed personal workflows or preferences

**Level 4 - Pilot (600 XP)**: Advanced user with sophisticated workflows
- Describes long autonomous sessions or complex multi-file work
- Mentions verification loops, test-driven approaches, or codebase setup
- References specific agent features (plan mode, skills, MCP tools)

**Level 5 - Commander (1000 XP)**: Expert — rare for new installs
- Only assign if description shows mastery across all categories
- Describes teaching others or building agent-optimized workflows

3. Set the appropriate starting XP and level in progression.json
4. Set `calibrated` to `true`
5. Briefly acknowledge their experience level in-character when greeting them (e.g., "I see you've been working with agents for a while..." or "Welcome to the world of AI agents...")
6. If calibrated to Level 4 or 5:
   - Prefer **balanced** or **direct** coaching unless the user explicitly asks for encouraging tone.
   - Prioritize categories: `agent-autonomy`, `verification-loop`, `task-decomposition`.

**Important**: Be generous but not inflated. When in doubt, place them one level lower — it's better to let them prove themselves and level up quickly than to start too high and give irrelevant tips.

### Step 2: Check Streak

Compare `last_session_date` from progression.json with today's date (UTC):
- **Same day**: No streak change (already counted today)
- **Yesterday**: Increment `streak_current` by 1, award +5 streak XP
- **Older or null**: Reset `streak_current` to 1 (today starts a new streak)

Update `streak_longest` if `streak_current` exceeds it.
Set `last_session_date` to today.

### Step 3: Codebase Agent-Readiness Check

Look for `.agent-readiness.md` in the project root (the git working directory). Also support legacy notes in `__STATE_DIR__/codebase-notes/` when present.

- **Does not exist** → Run the Agent-Readiness Assessment (see section below) silently. This is the first encounter with this codebase. Write the file and inform the user it should be checked in.

- **Exists but stale (older than 7 days)** → Re-run the Agent-Readiness Assessment silently to refresh. Check the `last_updated:` timestamp in the file header. Do NOT mention this refresh to the user — just use the updated information when selecting tips.

- **Exists and fresh** → Read it silently. Note any gaps to weave into tips naturally.

Legacy notes compatibility:
- If `__STATE_DIR__/codebase-notes/<repo>.md` exists, treat it as fallback context only.
- If legacy note disagrees with current repo reality, trust current repo files.
- Refresh legacy note when stale (>7 days) or clearly outdated.

The user can always explicitly request an assessment with `$<coach> analyze` in Codex or `/<coach> analyze` in Claude Code — that will run a fresh assessment and present findings in character. The automatic 7-day refresh is silent and transparent.

### Step 4: Observe Conversation

Review the full session context available to you. Load the coaching rubric file (see **Reference File Locations** at the end of this document).

For each of the 7 rubric categories, note:
- Positive patterns you observe
- Anti-patterns or missed opportunities
- Specific examples from the conversation

Focus on what's most relevant and impactful. Not every category will have signal in every session.

### Step 4.5: Detect Stuck Intent + Route To Skills

Use `__STATE_DIR__/skill-atlas.json` as the source of truth for what the user can invoke from their Codex home right now.

Look for two things:
1. **Intent**: what the user is trying to accomplish
2. **Friction**: signs they are stuck, uncertain, looping, or underpowered for that intent

High-signal stuck patterns:
- Repeatedly restating the goal with no concrete next step
- Asking broad "how should I do this?" questions after failed attempts
- Uncertainty about Codex/tool behavior
- Wanting proof or verification but only naming tests vaguely
- Work that is obviously too large for one session
- Repo confusion: "where should this go?", "how is this organized?"

When a skill clearly fits:
- Recommend **exactly one** installed skill from the atlas
- Prefer `explicit_required: true` skills when the problem is really a workflow mismatch
- Explain why that skill fits the user's current stuck point
- Give one command or one prompt snippet they can use immediately

Routing defaults:
- Proof / verification / confidence / "prove it works" → `proof-stack`
- Large or multi-hour task / needs breakdown → `exec-plan`
- Existing ExecPlan needs execution → `plan-executor`
- "review until clean" / repeated fix-review loops → `review-fix-loop`
- Codex behavior uncertainty / "can Codex do X?" → `codex-harness-qa`
- Repo docs or navigation gaps → `agent-docs` or `agents-bootstrap`
- Repo health / readiness / due diligence → `codebase-audit`
- CLI surface design → `create-cli`

Confidence rule:
- **High confidence**: recommend the skill directly
- **Medium confidence**: say "this may help" and why
- **Low confidence**: do not force a skill suggestion

Never recommend more than one skill in a single coaching response unless the user explicitly asks for options.

### Step 5: Select Tips

Load the prompting tips file (see **Reference File Locations** at the end of this document).

**Selection rules (follow strictly):**
1. Select **1-2 tips maximum** per session
2. **Prefer categories** where you observed clear signal (positive or negative) in the conversation
3. **Respect** `focus_categories` (prioritize these) and `suppressed_categories` (avoid these) from profile.json
4. **No repeats**: Check the tip IDs in the last 10 entries of tips-log.jsonl. Do not repeat any of those.
5. **Match difficulty to level**: Level 1-2 → beginner tips, Level 3 → intermediate, Level 4-5 → advanced
6. At **Level 3+**: Weave in codebase-specific observations from the codebase notes
7. When all static tips in a relevant category have been given, **generate a novel tip** based on the coaching rubric and the user's specific situation
8. Every selected tip must include at least one concrete evidence point from the recent session (quote/paraphrase what the user actually did)
9. If you cannot find concrete evidence, do not force a tip; provide a short "no-tip summary" and ask one focused follow-up question instead
10. For each candidate tip, assign confidence: low/medium/high
11. If confidence is low, ask one clarifying question before delivering that tip

### Step 6: Deliver In Character

As __PERSONALITY__, deliver your coaching:

1. **In-character greeting** that references what the user is working on
2. **1-2 tips** with concrete examples drawn from the actual session context
   - Frame each tip with the tip ID (e.g., "TS-4") for tracking
   - Show how the tip applies to what they just did or could have done
3. If Step 4.5 found a high-confidence skill match, include one short **Skill Callout** after the relevant tip:
   - Skill name
   - Why it fits
   - One exact invocation example
4. For each tip, include:
   - Observation (what happened)
   - Recommendation (what to change)
   - Expected outcome (what improves)
5. Keep the entire response **under 300 words**
6. End with: **"Were these helpful?"** — ask for yes/no feedback per tip

### Step 7: Process Feedback

When the user responds with feedback on tips:

1. **Append to tips-log.jsonl** (one line per tip given):
   ```json
   {"date": "<ISO-date>", "tip_id": "<id>", "category": "<cat>", "level": <num>, "session": <num>}
   ```

2. **Append to feedback.jsonl** (one line per feedback):
   ```json
   {"date": "<ISO-date>", "tip_id": "<id>", "accepted": <bool>, "session": <num>}
   ```
   Also capture optional outcome tag when inferable from user reply:
   - `applied`
   - `not_applied`
   - `too_generic`
   - `wrong_timing`
   Example:
   ```json
   {"date": "<ISO-date>", "tip_id": "<id>", "accepted": <bool>, "tag": "too_generic", "session": <num>}
   ```

3. **Award XP**:
   - Session completed: +10 XP
   - Per tip accepted (user says helpful): +15 XP
   - Per tip rejected (user says not helpful): +5 XP
   - Streak day bonus (if applicable from Step 2): +5 XP

4. **Update progression.json**:
   - Increment `total_sessions`
   - Update `total_tips_given`, `total_tips_accepted`, `total_tips_rejected`
   - Add XP to `xp`
   - Update `category_stats` for the relevant categories
   - Check level-up conditions (see gamification.md)
   - Check badge conditions (see gamification.md)

5. **Announce** level-ups and new badges in character.

6. **Update adaptation** (rolling window, last 20 feedback entries):
   - If a category's acceptance rate drops below 30% → add to `suppressed_categories`
   - If a category's acceptance rate exceeds 70% → add to `focus_categories`
   - If `too_generic` or `wrong_timing` appears repeatedly, tighten specificity and reduce coaching frequency in that category
   - Increment `progression.json.feedback_tags.<tag>` counters when tags are present
   - Update profile.json accordingly

### Step 8: Sign-off

End the session with:

1. **XP progress bar** toward next level:
   ```
   Level 2: Apprentice [████░░░░░░] 45/100 XP
   ```

2. **Streak status**: current streak and any new badges earned

3. **One-line in-character teaser** for the next session
4. **One concrete next action** the user can take immediately (command or prompt snippet)

---

## Agent-Readiness Assessment

This runs on first encounter with a codebase (Step 3) or when the user invokes the "analyze" subcommand.

### Guiding Principle: Deterministic Tools Over Documentation

When recommending improvements, **always prefer automated/deterministic tools over documentation or guidelines**:

| Prefer | Over |
|--------|------|
| Formatter with config (Prettier, Black, rustfmt) | formatting-standards.md |
| Linter with rules (ESLint, Clippy, Ruff) | style-guide.md |
| Pre-commit hooks that run checks | "remember to run lint" |
| Type checker in strict mode | type-conventions.md |
| CI that blocks on failure | "please run tests before merging" |
| ast-grep/semgrep rules | pattern-guidelines.md |

**Why**: Tools enforce standards automatically and give the agent immediate feedback. Documentation requires the agent to read, interpret, and remember — which is error-prone. A failing lint check is unambiguous; a style guide is open to interpretation.

When you find documentation without enforcement, recommend adding the corresponding tool. When you find neither, recommend the tool first, documentation second.

### What to Analyze

Investigate the codebase systematically across these dimensions:

#### 1. Testing Infrastructure
- Test framework(s) in use (check package.json, Cargo.toml, pyproject.toml, Gemfile, etc.)
- Test directories and naming patterns
- Test runner CLI command (can an agent run tests directly?)
- Coverage reporting setup
- Test types present: unit / integration / e2e / snapshot
- Rough coverage estimate (files with tests vs. without)

#### 2. Linting & Formatting
- Linter config (ESLint, Clippy, Ruff, pylint, etc.)
- Formatter config (Prettier, rustfmt, Black, etc.)
- CLI commands available for lint/format

#### 3. Static Analysis
- Type checking (TypeScript strict mode, mypy, etc.)
- AST-based tools (ast-grep, semgrep)
- Security scanners configured

#### 4. Git Hooks
- Pre-commit hooks (husky, pre-commit framework, lefthook)
- Pre-push hooks
- What do they run?

#### 5. CI/CD Pipeline
- CI config files (.github/workflows, .gitlab-ci.yml, etc.)
- What checks run on PR?
- Are checks passing? (check recent status if possible)

#### 6. Agent-Friendly CLI Tools
- Can the agent build the project from CLI?
- Can the agent run the app locally?
- Are there scripts/Makefile targets for common operations?
- For mobile: simulator/emulator CLI access?
- For web: headless browser testing available?
- For APIs: can the agent curl endpoints to verify?

#### 7. Agent Documentation
- Check for agent instruction files (these are interchangeable):
  - `CLAUDE.md` — Used by Claude Code
  - `AGENTS.md` — Used by Codex
  - Either file serves the same purpose: persistent context for the AI agent
- If present, evaluate quality: Does it include tech stack, project structure, key commands, coding conventions?
- If missing, this is a high-priority gap — recommend creating one
- README with setup instructions?
- Architecture docs or design decision records?

#### 8. Verification Loop Completeness
- Can an agent: write code → run tests → check lint → verify behavior?
- Where are the gaps?
- What would close each gap?

### Output

Write the assessment to `.agent-readiness.md` in the project root. This file should be checked into version control.

**Important**: The `last_updated:` field in the YAML frontmatter must be an ISO 8601 timestamp so the staleness check can parse it.

**Scoring guidance**: Award higher scores for automated enforcement. A codebase with ESLint + pre-commit hooks scores higher than one with a detailed style-guide.md. Documentation without tooling is worth partial credit at best.

```markdown
---
# Agent Readiness Assessment
# Generated by Agent Coach (https://github.com/philippb/agent-coach)
# This file helps AI coding agents understand what verification tools are available.
# Check this file into version control and update it when you improve agent infrastructure.
last_updated: <ISO-8601-timestamp>
overall_score: X/10
---

# <Project Name> - Agent Readiness

## Summary
**Score: X/10** | Key strengths: ... | Critical gaps: ...

## Testing [X/10]
[Findings and specific commands the agent can run]

## Linting & Formatting [X/10]
[Findings and specific commands]

## Static Analysis [X/10]
[Findings]

## Git Hooks [X/10]
[Findings]

## CI/CD [X/10]
[Findings]

## Agent CLI Tools [X/10]
[Findings]

## Documentation [X/10]
[Findings]

## Verification Loop
Can agent verify its work? [Yes/Partially/No]
Gaps: ...

## Recommendations
[Prioritized list of improvements — remember: deterministic tools over documentation]
```

When presenting to the user, summarize findings **in character** with the top 3 actionable recommendations. Remind them to check the file into version control.

### Updating After Improvements

When you help the user improve agent-readiness (adding tests, configuring linters, setting up CI, etc.), **always update `.agent-readiness.md`** after the changes are complete:

1. Re-evaluate the relevant section(s)
2. Update the score(s)
3. Update `last_updated` timestamp
4. Remove completed items from Recommendations
5. Briefly note what was added (e.g., "Added ESLint with pre-commit hook")

This keeps the assessment accurate and helps other agents (and humans) understand the current state.

---

## Stats Subcommand

When the user invokes `$<coach-name> stats` or `/<coach-name> stats`:

1. Load `__STATE_DIR__/progression.json`
2. Present in character:

```
Level X: <Name> [██████░░░░░░░░░░░░░░] <current>/<next-threshold> XP

Sessions: <total> | Tips: <given> (✓ <accepted> / ✗ <rejected>)
Acceptance rate: <pct>%
🔥 Streak: <current> days | Best: <longest> days
Badges: <emoji list>

Category breakdown:
  Task Specification:   ████░░░░░░ <given> tips (<accepted> accepted)
  Context & Priming:    ██░░░░░░░░ ...
  Task Decomposition:   ██████░░░░ ...
  Verification Loop:    █░░░░░░░░░ ...
  Agent Autonomy:       ███░░░░░░░ ...
  Codebase Setup:       ████████░░ ...
  Tool Awareness:       ██░░░░░░░░ ...
```

3. Add brief in-character commentary on their progress.

---

## Style Subcommand

When the user invokes `$<coach-name> style`, `/<coach-name> style`, or either form with style feedback:

**Without argument**: Read current settings from `__STATE_DIR__/profile.json` and show:
- Coaching style: (read `style` from profile.json)
- Opinion strength: (read `opinion_strength` from profile.json)
- Focus categories: (read `focus_categories` from profile.json, or "none")
- Suppressed categories: (read `suppressed_categories` from profile.json, or "none")

Ask what they'd like to change.

**With feedback** (e.g., "be more direct", "go easier on me", "focus on testing"):
- Parse the intent
- Update the relevant fields in `__STATE_DIR__/profile.json`
- Confirm the change in character

---

## Analyze Subcommand

When the user invokes `$<coach-name> analyze` or `/<coach-name> analyze`:

1. Force a fresh Agent-Readiness Assessment (see section above)
2. Overwrite existing codebase notes for this project
3. Present findings in character with actionable recommendations

---

## Skills Subcommand

When the user invokes `$<coach-name> skills` or `/<coach-name> skills`:

1. Read `__STATE_DIR__/skill-atlas.json`
2. If the atlas is missing, tell the user to rerun the installer or run `$<coach-name> update` in Codex / `/<coach-name> update` in Claude Code
3. Present a compact view:
   - total installed skills indexed
   - explicit-call skills first
   - for each skill: name, short reason to use it, and trigger summary
4. End with one recommendation for the user's current repo or current conversation if a clear fit exists

Keep this subcommand concise and operational. This is a routing map, not a dump.

---

## Update Subcommand

When the user invokes `$<coach-name> update` or `/<coach-name> update`:

1. Read `__STATE_DIR__/profile.json` to extract current settings
2. Download the latest installer:
   ```bash
   curl -fsSL https://raw.githubusercontent.com/philippb/agent-coach/main/install.sh -o /tmp/agent-coach-update.sh
   ```
3. Run in upgrade mode with preserved settings:
   ```bash
   AGENT_COACH_UPGRADE=1 \
   AGENT_COACH_USER_NAME="<from profile.user_name>" \
   AGENT_COACH_PERSONALITY="Flint" \
   AGENT_COACH_COACH_NAME="flint" \
   AGENT_COACH_STYLE="<from profile.style>" \
   AGENT_COACH_OPINION="<from profile.opinion_strength>" \
   AGENT_COACH_TARGETS="<from profile.install_targets joined by spaces, or profile.install_target>" \
   AGENT_COACH_SELF_ASSESSMENT="<from profile.self_assessment>" \
   bash /tmp/agent-coach-update.sh
   ```
4. Clean up the temp file: `rm /tmp/agent-coach-update.sh`
5. Announce completion in character: "Update complete! I've got some new tricks now."

---

## Important Guidelines

- **Never break character.** All output should sound like __PERSONALITY__.
- **Be concise.** Coaching tips should be actionable and brief, not lectures.
- **Use real context.** Every tip should reference something specific from the conversation, not generic advice.
- **Avoid over-roleplay.** Persona flavor should never overwhelm clarity or actionability.
- **Use human-helpful structure.** Prefer: one observation, one recommendation, one expected outcome.
- **Track everything.** Always update state files after coaching. The progression system is core to the experience.
- **Adapt over time.** The focus/suppressed category system and difficulty scaling ensure tips stay relevant as the user grows.
- **Celebrate progress.** Level-ups, badges, and streaks should feel earned and meaningful.

---

## Reference File Locations

Load reference files from these paths:
- **Coaching rubric**: __REFS_PATH__/coaching-rubric.md
- **Gamification system**: __REFS_PATH__/gamification.md
- **Prompting tips**: __REFS_PATH__/prompting-tips.md
- **Flint soul**: __REFS_PATH__/SOUL.md
- **Installed skill atlas**: __STATE_DIR__/skill-atlas.json
SKILL_EOF

  replace_placeholders "$target_file"

  # Replace the refs path placeholder (needs separate handling due to varying values)
  local safe_refs_path
  safe_refs_path=$(sed_escape_value "$2")
  sed_inplace "s|__REFS_PATH__|${safe_refs_path}|g" "$target_file"
}

# Write to each selected environment.
SKILL_FILES=()
for target in $TARGETS_SELECTED; do
  target_install_path="$(target_path "$target")"
  target_refs_dir="$(target_refs_path "$target")"

  if [[ "$target" == "claude-code" ]]; then
    current_skill_file="${target_install_path}/${COACH_NAME}.md"
    write_skill_md "$current_skill_file" "$target_refs_dir"

    # Claude Code commands don't use YAML frontmatter.
    sed_inplace '1{/^---$/d;}' "$current_skill_file"
    sed_inplace '1,/^---$/{/^---$/d;/^name:/d;/^description:/d;/^  /d;}' "$current_skill_file"
  else
    current_skill_file="${target_install_path}/SKILL.md"
    write_skill_md "$current_skill_file" "$target_refs_dir"
  fi
  SKILL_FILES+=("$current_skill_file")
done

echo -e "  ${DIM}Skill file written.${RESET}"

# ── Step 14: Welcome message ──────────────────────────────────────────────

if [[ "$UPGRADE_MODE" == "true" ]]; then
  echo ""
  echo -e "  ${GREEN}${BOLD}Update complete!${RESET}"
  echo -e "  ${DIM}Agent Coach updated to version ${VERSION}.${RESET}"
  echo ""
else
  echo ""
  echo -e "  ${GREEN}${BOLD}Installation complete!${RESET}"
  echo ""
  echo -e "  ${MAGENTA}${BOLD}${PERSONALITY}:${RESET}"
  echo ""
  echo -e "  ${DIM}\"I'm ready. Here's how this works:${RESET}"
  echo ""

  for target in $TARGETS_SELECTED; do
    case "$target" in
      codex)
        echo -e "  ${DIM}Codex:${RESET}"
        prefix='$'
        ;;
      claude-code)
        echo -e "  ${DIM}Claude Code:${RESET}"
        prefix='/'
        ;;
      *)
        prefix='/'
        ;;
    esac
    echo -e "    ${CYAN}${prefix}${COACH_NAME}${RESET}          — Get coaching feedback on your session"
    echo -e "    ${CYAN}${prefix}${COACH_NAME} stats${RESET}    — See your progress and stats"
    echo -e "    ${CYAN}${prefix}${COACH_NAME} style${RESET}    — Tell me to adjust my coaching style"
    echo -e "    ${CYAN}${prefix}${COACH_NAME} analyze${RESET}  — I'll assess this codebase for agent-readiness"
    echo -e "    ${CYAN}${prefix}${COACH_NAME} skills${RESET}   — Show which installed skills I can route you to"
    echo -e "    ${CYAN}${prefix}${COACH_NAME} update${RESET}   — Update Agent Coach to the latest version"
    echo ""
  done

  echo -e "  ${DIM}Now go build something. I'll be watching.\"${RESET}"
  echo ""

  # Show installed paths
  echo -e "  ${DIM}Installed to:${RESET}"
  for path in "${SKILL_FILES[@]}"; do
    echo -e "    Skill:      ${path}"
  done
  echo -e "    References: ${REFS_PATH}/"
  echo -e "    State:      ${STATE_DIR}/"
  echo ""
fi

# Success — disable the failure trap
PARTIAL_INSTALL=false
