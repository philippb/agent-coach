#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
  mkdir -p "$HOME/.codex/skills/proof-stack"
  cat >"$HOME/.codex/skills/proof-stack/SKILL.md" <<'EOF'
---
name: proof-stack
description: Build and execute a highest-signal-first verification stack.
---
EOF
}

@test "install.sh creates state and skill files" {
  run env HOME="$HOME" bash "$BATS_TEST_DIRNAME/../install.sh" <<'INSTALL_INPUT'
Philipp
2
2

1
INSTALL_INPUT

  [ "$status" -eq 0 ]
  [ -f "$HOME/.agent-coach/profile.json" ]
  [ -f "$HOME/.agent-coach/progression.json" ]
  [ -f "$HOME/.agent-coach/skill-atlas.json" ]
  [ -f "$HOME/.codex/skills/flint/SKILL.md" ]
  [ -f "$HOME/.codex/skills/flint/references/coaching-rubric.md" ]
  [ -f "$HOME/.codex/skills/flint/references/openclaw-practices.md" ]
  [ -f "$HOME/.codex/skills/flint/references/SOUL.md" ]
  grep -q '"coach_name": "flint"' "$HOME/.agent-coach/profile.json"
  grep -q '"personality": "Flint"' "$HOME/.agent-coach/profile.json"
  grep -q '"interaction_mode": "strict"' "$HOME/.agent-coach/profile.json"
  grep -q '"progress_pulses"' "$HOME/.agent-coach/profile.json"
  grep -q '"welcomed": false' "$HOME/.agent-coach/progression.json"
  grep -q '"feedback_tags"' "$HOME/.agent-coach/progression.json"
  grep -q '"name": "proof-stack"' "$HOME/.agent-coach/skill-atlas.json"
  grep -q '## Main Coaching Flow' "$HOME/.codex/skills/flint/SKILL.md"
  grep -q '### Step 1.4: First-Run Welcome' "$HOME/.codex/skills/flint/SKILL.md"
  grep -q 'No tips, no rubric IDs' "$HOME/.codex/skills/flint/SKILL.md"
  grep -q '### OpenClaw-Level Guidance' "$HOME/.codex/skills/flint/SKILL.md"
  grep -q '## Skills Subcommand' "$HOME/.codex/skills/flint/SKILL.md"
  grep -q 'OpenClaw Practices' "$HOME/.codex/skills/flint/references/openclaw-practices.md"
  grep -q "Be the assistant you'd actually want to talk to at 2am" "$HOME/.codex/skills/flint/references/SOUL.md"
  printf '%s' "$output" | grep -q '\$flint stats'
  grep -q '"install_targets": \["codex"\]' "$HOME/.agent-coach/profile.json"
}

@test "install.sh can install Flint into Codex and Claude" {
  mkdir -p "$HOME/.claude"

  run env HOME="$HOME" bash "$BATS_TEST_DIRNAME/../install.sh" <<'INSTALL_INPUT'
Philipp
2
2

1 2
INSTALL_INPUT

  [ "$status" -eq 0 ]
  [ -f "$HOME/.codex/skills/flint/SKILL.md" ]
  [ -f "$HOME/.claude/commands/flint.md" ]
  printf '%s' "$output" | grep -q '\$flint stats'
  printf '%s' "$output" | grep -q '/flint stats'
  grep -q '"install_targets": \["codex", "claude-code"\]' "$HOME/.agent-coach/profile.json"
}
