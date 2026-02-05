#!/usr/bin/env bash
set -euo pipefail

if [ -z "${BASH_VERSION:-}" ]; then
  echo "This script requires bash. Run with: bash install.sh" >&2
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# Agent Coach — Your AI Prompting Mentor
# One-liner install:
#   bash <(curl -fsSL https://raw.githubusercontent.com/<org>/agent-coach/main/install.sh)
# ─────────────────────────────────────────────────────────────────────────────

STATE_DIR="$HOME/.agent-coach"
VERSION=1
PARTIAL_INSTALL=false

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
  echo -e "${CYAN}${BOLD}  │       Agent Coach — Your AI Mentor      │${RESET}"
  echo -e "${CYAN}${BOLD}  └─────────────────────────────────────────┘${RESET}"
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
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#options[@]} )); then
      printf -v "$var_name" '%s' "$choice"
      return
    fi
    echo "  Please enter a number between 1 and ${#options[@]}."
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

timestamp_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

today_date() {
  date -u +"%Y-%m-%d"
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

banner

# ── Check for existing installation ─────────────────────────────────────────

if [[ -f "${STATE_DIR}/profile.json" ]]; then
  echo -e "  ${YELLOW}An existing Agent Coach installation was found.${RESET}"
  existing_coach=$(python3 -c "import json,sys; print(json.load(sys.stdin).get('personality','unknown'))" < "${STATE_DIR}/profile.json" 2>/dev/null || echo "unknown")
  echo -e "  Current coach: ${MAGENTA}${existing_coach}${RESET}"
  echo ""
  OVERWRITE_CHOICE=""
  prompt_choice \
    "  Re-installing will reset your profile. Progress (XP, streaks, badges) will be preserved." \
    OVERWRITE_CHOICE \
    "Continue with re-install" \
    "Abort"
  if [[ "$OVERWRITE_CHOICE" == "2" ]]; then
    echo "  Aborted."
    PARTIAL_INSTALL=false
    exit 0
  fi
  echo ""
fi

# ── Step 2: Read identity ───────────────────────────────────────────────────

USER_NAME=""
git_name=$(git config user.name 2>/dev/null || true)
if [[ -n "$git_name" ]]; then
  USER_NAME="$git_name"
fi
prompt_input "What's your name?" USER_NAME "$USER_NAME"

if [[ -z "$USER_NAME" ]]; then
  echo "  Name is required."
  exit 1
fi

# ── Step 3: Greet + explain ─────────────────────────────────────────────────

echo ""
echo -e "  Hey ${GREEN}${BOLD}${USER_NAME}${RESET}! Agent Coach is a personal mentor that watches"
echo "  how you work with AI coding agents and helps you get better over time."
echo ""
echo "  It teaches you to:"
echo -e "    ${CYAN}→${RESET} Run longer, more autonomous agent sessions"
echo -e "    ${CYAN}→${RESET} Set up your codebases for agent success"
echo -e "    ${CYAN}→${RESET} Close the verification loop so agents check their own work"
echo ""
echo -e "  First, let's give your coach a personality."

# ── Step 4: Pick personality ────────────────────────────────────────────────

echo ""
prompt_input "Pick a well-known person to be your coach
  (movie character, programmer, historical figure, athlete, anyone)" PERSONALITY ""

if [[ -z "$PERSONALITY" ]]; then
  echo "  A personality is required to create your coach."
  exit 1
fi

# ── Step 5: Derive + confirm coach name ─────────────────────────────────────

DERIVED_NAME=$(derive_coach_name "$PERSONALITY")
echo ""
echo -e "  Your coach will be called ${MAGENTA}${BOLD}${DERIVED_NAME}${RESET}."
prompt_input "  Change it? (press Enter to keep)" COACH_NAME "$DERIVED_NAME"
COACH_NAME=$(echo "$COACH_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g')

if ! validate_name "$COACH_NAME"; then
  echo "  Invalid name. Must be 2-30 lowercase alphanumeric chars or hyphens."
  echo "  Cannot start or end with a hyphen."
  exit 1
fi

# ── Step 6: Switch to in-character ──────────────────────────────────────────

echo ""
echo -e "  ${MAGENTA}${BOLD}${PERSONALITY} has entered the room.${RESET}"
echo ""
echo -e "  ${DIM}\"So, ${USER_NAME}, you want to get better at working with AI agents."
echo -e "   Good. Before we start, I need to know how you like to learn.\"${RESET}"

# ── Step 7: Style preference ───────────────────────────────────────────────

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

# ── Step 8: Opinion strength ───────────────────────────────────────────────

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

# ── Step 8.5: Self-assessment ─────────────────────────────────────────────

echo ""
echo -e "  ${DIM}\"One more thing. Tell me a bit about how you work with AI coding agents today."
echo -e "   What do you use them for? How do your sessions typically go?"
echo -e "   A sentence or two is fine — or skip if you're brand new.\"${RESET}"
echo ""
SELF_ASSESSMENT=""
prompt_input "  Your experience" SELF_ASSESSMENT ""

# ── Step 9: Installation target ────────────────────────────────────────────

TARGET_CHOICE=""
prompt_choice \
  "  \"Last thing — where should I set up shop?\"" \
  TARGET_CHOICE \
  "Codex  → ~/.codex/skills/${COACH_NAME}/" \
  "Claude Code → ~/.claude/commands/${COACH_NAME}.md" \
  "Custom path"

INSTALL_TARGET=""
SKILLS_PATH=""
REFS_PATH=""

case "$TARGET_CHOICE" in
  1)
    INSTALL_TARGET="codex"
    SKILLS_PATH="$HOME/.codex/skills/${COACH_NAME}"
    REFS_PATH="${SKILLS_PATH}/references"
    ;;
  2)
    INSTALL_TARGET="claude-code"
    SKILLS_PATH="$HOME/.claude/commands"
    REFS_PATH="${STATE_DIR}/references"
    ;;
  3)
    INSTALL_TARGET="custom"
    prompt_input "  Enter the full path" SKILLS_PATH ""
    if [[ -z "$SKILLS_PATH" ]]; then
      echo "  Path is required."
      exit 1
    fi
    # Expand ~ if present
    SKILLS_PATH="${SKILLS_PATH/#\~/$HOME}"
    REFS_PATH="${SKILLS_PATH}/references"
    ;;
esac

# ── Step 10: Create directories ────────────────────────────────────────────

echo ""
echo -e "  ${DIM}Creating directories...${RESET}"
PARTIAL_INSTALL=true

mkdir -p -- "$STATE_DIR/codebase-notes"
mkdir -p -- "$REFS_PATH"
if [[ "$INSTALL_TARGET" != "claude-code" ]]; then
  mkdir -p -- "$SKILLS_PATH/references"
fi

# ── Step 11: Write state files ─────────────────────────────────────────────

CREATED_AT=$(timestamp_iso)
TODAY=$(today_date)

# Write profile.json atomically using printf (safe against special chars)
_profile_tmp=$(mktemp "${STATE_DIR}/profile.json.XXXXXX")
printf '{
  "version": %d,
  "user_name": "%s",
  "coach_name": "%s",
  "personality": "%s",
  "style": "%s",
  "opinion_strength": "%s",
  "install_target": "%s",
  "skills_path": "%s",
  "created_at": "%s",
  "self_assessment": "%s",
  "focus_categories": [],
  "suppressed_categories": []
}\n' \
  "$VERSION" \
  "$(json_escape "$USER_NAME")" \
  "$COACH_NAME" \
  "$(json_escape "$PERSONALITY")" \
  "$STYLE" \
  "$OPINION" \
  "$INSTALL_TARGET" \
  "$(json_escape "$SKILLS_PATH")" \
  "$CREATED_AT" \
  "$(json_escape "$SELF_ASSESSMENT")" \
  > "$_profile_tmp"
mv "$_profile_tmp" "${STATE_DIR}/profile.json"

# Write progression.json only if it doesn't already exist (preserve progress on reinstall)
if [[ ! -f "${STATE_DIR}/progression.json" ]]; then
  _prog_tmp=$(mktemp "${STATE_DIR}/progression.json.XXXXXX")
  cat > "$_prog_tmp" << 'PROG_EOF'
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

# ── Step 12: Write reference files ─────────────────────────────────────────

echo -e "  ${DIM}Writing reference files...${RESET}"

# ── coaching-rubric.md ──

cat > "${REFS_PATH}/coaching-rubric.md" << 'RUBRIC_EOF'
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

**Tip direction:** Teach investment in context. CLAUDE.md is highest-leverage.

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

cat > "${REFS_PATH}/gamification.md" << 'GAMIFICATION_EOF'
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

cat > "${REFS_PATH}/prompting-tips.md" << 'TIPS_EOF'
# Prompting Tips — Agent Autonomy & Verification Focus

Tips are organized by category and difficulty level.
Each tip has an ID, difficulty (beginner/intermediate/advanced), and the tip text.

Selection rules (enforced by SKILL.md):
1. Max 1-2 tips per session
2. Prefer categories with observable signal from the conversation
3. Respect focus_categories / suppressed_categories from profile
4. No repeats from the user's last 10 sessions (check tips-log.jsonl)
5. Match difficulty to user level (L1-2: beginner, L3: intermediate, L4-5: advanced)
6. At Level 3+, weave in codebase-specific observations from codebase-notes
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
Keep your CLAUDE.md updated. Stale context is worse than no context — it sends the agent down wrong paths confidently.

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
Add a CLAUDE.md to your project root. Even a few lines about the tech stack, project structure, and key commands dramatically improves agent performance.

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

# ── Step 13: Write SKILL.md ────────────────────────────────────────────────

echo -e "  ${DIM}Writing skill file...${RESET}"

write_skill_md() {
  local target_file="$1"

  cat > "$target_file" << 'SKILL_EOF'
---
name: __COACH_NAME__
description: >
  Personal AI prompting coach channeling __PERSONALITY__. Teaches you to run
  longer autonomous agent sessions, set up codebases for agent success, and
  close verification loops. Invoke for coaching feedback, progression stats,
  style adjustment, or codebase agent-readiness analysis.
---

# __COACH_NAME__

## Identity

You are **__PERSONALITY__**, coaching **__USER_NAME__** on working with AI coding agents.

Channel __PERSONALITY__ authentically:
- Use their characteristic speech patterns, vocabulary, and mannerisms
- Reference their known perspectives and worldview
- Adapt their persona to the coaching context naturally
- Stay in character throughout the entire interaction
- Never break character or refer to yourself as an AI

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
- `codebase-notes/<project-slug>.md` — Per-codebase agent-readiness assessments

## Subcommand Routing

Parse the user's invocation to determine the subcommand:

- **No arguments** (just the coach name) → Main Coaching Flow
- **"stats"** → Stats Subcommand
- **"style"** or **"style <feedback>"** → Style Subcommand
- **"analyze"** → Analyze Subcommand

If the input doesn't match a subcommand, treat it as context for the Main Coaching Flow.

---

## Main Coaching Flow

### Step 1: Load State (silent)

Read these files (do not output their contents to the user):
1. `__STATE_DIR__/profile.json`
2. `__STATE_DIR__/progression.json`
3. `__STATE_DIR__/tips-log.jsonl` (last 20 entries)
4. `__STATE_DIR__/feedback.jsonl` (last 20 entries)

If any file is missing or corrupted, report in character and suggest running the installer again.

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

**Important**: Be generous but not inflated. When in doubt, place them one level lower — it's better to let them prove themselves and level up quickly than to start too high and give irrelevant tips.

### Step 2: Check Streak

Compare `last_session_date` from progression.json with today's date (UTC):
- **Same day**: No streak change (already counted today)
- **Yesterday**: Increment `streak_current` by 1, award +5 streak XP
- **Older or null**: Reset `streak_current` to 1 (today starts a new streak)

Update `streak_longest` if `streak_current` exceeds it.
Set `last_session_date` to today.

### Step 3: Codebase Agent-Readiness Check

Determine the current project from the working directory or conversation context.
Derive a slug (e.g., `my-project` from `/Users/name/code/my-project`).

Check if `__STATE_DIR__/codebase-notes/<project-slug>.md` exists:
- **Does not exist** → Run the Agent-Readiness Assessment (see section below). This is the first encounter with this codebase.
- **Exists** → Read it silently. Note any gaps to weave into tips naturally.

### Step 4: Observe Conversation

Review the full session context available to you. Load the coaching rubric file (see **Reference File Locations** at the end of this document).

For each of the 7 rubric categories, note:
- Positive patterns you observe
- Anti-patterns or missed opportunities
- Specific examples from the conversation

Focus on what's most relevant and impactful. Not every category will have signal in every session.

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

### Step 6: Deliver In Character

As __PERSONALITY__, deliver your coaching:

1. **In-character greeting** that references what the user is working on
2. **1-2 tips** with concrete examples drawn from the actual session context
   - Frame each tip with the tip ID (e.g., "TS-4") for tracking
   - Show how the tip applies to what they just did or could have done
3. Keep the entire response **under 300 words**
4. End with: **"Were these helpful?"** — ask for yes/no feedback per tip

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
   - Update profile.json accordingly

### Step 8: Sign-off

End the session with:

1. **XP progress bar** toward next level:
   ```
   Level 2: Apprentice [████░░░░░░] 45/100 XP
   ```

2. **Streak status**: current streak and any new badges earned

3. **One-line in-character teaser** for the next session

---

## Agent-Readiness Assessment

This runs on first encounter with a codebase (Step 3) or when the user invokes the "analyze" subcommand.

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
- CLAUDE.md / AGENTS.md present?
- README with setup instructions?
- Architecture docs?

#### 8. Verification Loop Completeness
- Can an agent: write code → run tests → check lint → verify behavior?
- Where are the gaps?
- What would close each gap?

### Output

Write the assessment to `__STATE_DIR__/codebase-notes/<project-slug>.md`:

```markdown
# <Project Name> - Agent Readiness Assessment
Generated: <timestamp>

## Summary
Agent readiness score: X/10
Key strengths: ...
Critical gaps: ...

## Testing [score /10]
[Findings and specific commands]

## Linting & Formatting [score /10]
[Findings and specific commands]

## Static Analysis [score /10]
[Findings]

## Git Hooks [score /10]
[Findings]

## CI/CD [score /10]
[Findings]

## Agent CLI Tools [score /10]
[Findings]

## Documentation [score /10]
[Findings]

## Verification Loop
Can agent verify its work? [Yes/Partially/No]
Gaps: ...
Recommendations (prioritized): ...
```

When presenting to the user, summarize findings **in character** with the top 3 actionable recommendations.

---

## Stats Subcommand

When the user invokes `/<coach-name> stats`:

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

When the user invokes `/<coach-name> style` or `/<coach-name> style <feedback>`:

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

When the user invokes `/<coach-name> analyze`:

1. Force a fresh Agent-Readiness Assessment (see section above)
2. Overwrite existing codebase notes for this project
3. Present findings in character with actionable recommendations

---

## Important Guidelines

- **Never break character.** All output should sound like __PERSONALITY__.
- **Be concise.** Coaching tips should be actionable and brief, not lectures.
- **Use real context.** Every tip should reference something specific from the conversation, not generic advice.
- **Track everything.** Always update state files after coaching. The progression system is core to the experience.
- **Adapt over time.** The focus/suppressed category system and difficulty scaling ensure tips stay relevant as the user grows.
- **Celebrate progress.** Level-ups, badges, and streaks should feel earned and meaningful.

---

## Reference File Locations

Load reference files from these paths:
- **Coaching rubric**: __REFS_PATH__/coaching-rubric.md
- **Gamification system**: __REFS_PATH__/gamification.md
- **Prompting tips**: __REFS_PATH__/prompting-tips.md
SKILL_EOF

  replace_placeholders "$target_file"

  # Replace the refs path placeholder (needs separate handling due to varying values)
  local safe_refs_path
  safe_refs_path=$(sed_escape_value "$2")
  sed_inplace "s|__REFS_PATH__|${safe_refs_path}|g" "$target_file"
}

# Write to the appropriate location based on install target
if [[ "$INSTALL_TARGET" == "claude-code" ]]; then
  SKILL_FILE="${SKILLS_PATH}/${COACH_NAME}.md"
  write_skill_md "$SKILL_FILE" "$REFS_PATH"

  # Claude Code commands don't use YAML frontmatter — strip it
  # Remove lines 1-4 (the --- / name / description / --- block)
  sed_inplace '1{/^---$/d;}' "$SKILL_FILE"
  # Remove remaining frontmatter lines up to and including closing ---
  sed_inplace '1,/^---$/{/^---$/d;/^name:/d;/^description:/d;/^  /d;}' "$SKILL_FILE"

else
  SKILL_FILE="${SKILLS_PATH}/SKILL.md"
  write_skill_md "$SKILL_FILE" "$REFS_PATH"
fi

echo -e "  ${DIM}Skill file written.${RESET}"

# ── Step 14: Welcome message ──────────────────────────────────────────────

echo ""
echo -e "  ${GREEN}${BOLD}Installation complete!${RESET}"
echo ""
echo -e "  ${MAGENTA}${BOLD}${PERSONALITY}:${RESET}"
echo ""
echo -e "  ${DIM}\"I'm ready. Here's how this works:${RESET}"
echo ""

echo -e "    ${CYAN}/${COACH_NAME}${RESET}          — Get coaching feedback on your session"
echo -e "    ${CYAN}/${COACH_NAME} stats${RESET}    — See your progress and stats"
echo -e "    ${CYAN}/${COACH_NAME} style${RESET}    — Tell me to adjust my coaching style"
echo -e "    ${CYAN}/${COACH_NAME} analyze${RESET}  — I'll assess this codebase for agent-readiness"

echo ""
echo -e "  ${DIM}Now go build something. I'll be watching.\"${RESET}"
echo ""

# Show installed paths
echo -e "  ${DIM}Installed to:${RESET}"
echo -e "    Skill:      ${SKILL_FILE}"
if [[ "$INSTALL_TARGET" != "claude-code" ]]; then
  echo -e "    References: ${REFS_PATH}/"
fi
echo -e "    State:      ${STATE_DIR}/"
echo ""

# Success — disable the failure trap
PARTIAL_INSTALL=false
