#!/usr/bin/env bats

setup() {
  export HOME="$BATS_TEST_TMPDIR/home"
  mkdir -p "$HOME"
}

@test "install.sh creates state and skill files" {
  run env HOME="$HOME" bash "$BATS_TEST_DIRNAME/../install.sh" <<'INSTALL_INPUT'
Philipp
Yoda

2
2

1
INSTALL_INPUT

  [ "$status" -eq 0 ]
  [ -f "$HOME/.agent-coach/profile.json" ]
  [ -f "$HOME/.agent-coach/progression.json" ]
  [ -f "$HOME/.codex/skills/yoda/SKILL.md" ]
  [ -f "$HOME/.codex/skills/yoda/references/coaching-rubric.md" ]
  grep -q '"coach_name": "yoda"' "$HOME/.agent-coach/profile.json"
}
