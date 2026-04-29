# Agent Coach

Agent Coach is a personal prompting mentor for AI coding agents. It helps you get better at directing tools like Codex or Claude by giving focused coaching, building strong verification habits, and guiding you toward agent‑friendly codebases. The default coach is Flint: direct, witty, opinionated, and brief. The goal is simple: more reliable agent outcomes with less back‑and‑forth.

## Capabilities
- Turn vague requests into clear, testable prompts.
- Build a repeatable verification loop so agents can check their own work.
- Adapt coaching style to your preference: direct, balanced, or encouraging.
- Track progress with levels, streaks, and badges.
- Assess codebase readiness and get prioritized, practical upgrades.
- Guide a repo toward OpenClaw-level agent practices: repo contracts, cheap proof gates, reusable skills, behavior scenarios, and evidence discipline.

## How It Works
Flint observes your sessions and gives short, concrete tips tied to what you just did. When you want a snapshot of progress, you can ask for stats. When you want to improve a repository for agents, you can request a readiness analysis and a clear action plan. It also indexes the skills installed in your Codex home so it can route you to the right one when you are stuck.

## Typical Outcomes
- Clearer prompts that reduce guesswork.
- Faster, more autonomous agent sessions.
- Fewer regressions thanks to stronger verification habits.
- A codebase that both agents and humans can navigate with confidence.

## Game Your Progress

Level up your prompting skills and unlock achievements as you train with your coach.

### Levels

| Level | Title | XP Required |
|:-----:|-------|-------------|
| 1 | **Prompter** | 0 |
| 2 | **Apprentice** | 100 |
| 3 | **Navigator** | 300 |
| 4 | **Pilot** | 600 |
| 5 | **Commander** | 1000 |

Start as a Prompter learning the basics. Rise through the ranks as you master task specification, verification loops, and autonomous agent workflows. Reach Commander status and become the one who teaches others.

### Earn XP

| Action | XP |
|--------|---:|
| Complete a coaching session | +10 |
| Accept a helpful tip | +15 |
| Reject a tip (honesty counts!) | +5 |
| Maintain your daily streak | +5 |

### Unlock Badges

**Milestone Badges**
| Badge | How to Unlock |
|-------|---------------|
| 🥾 First Steps | Complete your first coaching session |
| 💯 Century Club | Reach 100 XP |
| 👑 Grand Master | Reach Level 5 |

**Streak Badges**
| Badge | How to Unlock |
|-------|---------------|
| 🔥 Streak Starter | 3-day coaching streak |
| ⚡ Streak Master | 7-day coaching streak |
| 🏆 Streak Legend | 30-day coaching streak |

**Mastery Badges** — Earn these by accepting 5 tips in a category
| Badge | Category |
|-------|----------|
| 📋 Spec Writer | Task Specification |
| 🧭 Context Master | Context & Priming |
| 🔪 Task Surgeon | Task Decomposition |
| 🔄 Loop Closer | Verification Loop |
| 🚀 Autonomy Ace | Agent Autonomy |
| 🏗️ Infrastructure Pro | Codebase Setup |
| 🛠️ Tool Wielder | Tool Awareness |

**Special Badges**
| Badge | How to Unlock |
|-------|---------------|
| 📚 Quick Study | Accept 5 tips in a row |
| 🗺️ Explorer | Run codebase assessments on 3 different projects |
| 🪞 Honest Critic | Reject 10 tips — your feedback shapes better coaching |

### Keep the Streak Alive

Use your coach on consecutive days to build your streak. Miss a day and it resets — but your longest streak is always remembered.

```
🔥 Streak: 12 days | 🏆 Best: 24 days
```

## How to Install
From this repo:

```bash
bash install.sh
```

If you prefer a one‑liner, use the hosted installer:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/philippb/agent-coach/main/install.sh)
```

## Getting Started
Run the installer in this repository, meet Flint, and use the coach commands it provides inside your AI tool.

The first time you invoke Flint, he starts with a short orientation instead of a full coaching report: what he does, how to talk to him, your current level/streak, and what to bring next. After that, use him on real work so the feedback is grounded in your actual prompt behavior.

Useful commands after install:
- `$flint` in Codex, or `/flint` in Claude Code, for feedback on your recent work
- `$flint skills` / `/flint skills` to see installed skills the coach can route you to
- `$flint analyze` / `/flint analyze` for a fresh repo readiness pass
- Ask `$flint what should I change in this repo?` for direct agent-readiness upgrades, or ask for a step-by-step path to OpenClaw-level practices

## Feedback
Have feedback or ideas? Please open a GitHub Issue on this repository.

## License
MIT (see `LICENSE`).
