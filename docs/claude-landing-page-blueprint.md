Here's the complete landing page content blueprint:

---

# Flint Agent Coach — Landing Page Blueprint

---

## 1. Sticky Nav Bar

**Layout:** Full-width, frosted glass backdrop. Logo left, links right. Thin bottom border with subtle glow.

| Element | Copy |
|---------|------|
| Brand name | `FLINT AGENT COACH` (with glowing period: `.`) |
| Nav link 1 | `Docs` → links to README |
| Nav link 2 | `GitHub` → links to repo |
| Nav link 3 | `Install` → anchor scrolls to install CTA |

---

## 2. Hero Section (first viewport, ~90vh)

**Layout:** Two-column grid (55/45 split). Left: text stack. Right: hero image. Vertically centered. The install command sits *above* the kicker as a floating chip — it's the first thing the eye hits. Generous top padding (~10vh) so the hero breathes below the nav.

**Spacing guidance:** The H1 should dominate. Lede text directly under it, tight. CTA row snug under lede. The command chip floats above the kicker with ~24px gap below it. Right-column image fills its container with rounded corners and a soft scanline overlay.

### Install command chip (top of left column)
```
$ bash <(curl -fsSL https://raw.githubusercontent.com/philippb/agent-coach/main/install.sh)
```
Button label: `Copy`

### Kicker (monospace, uppercase, accent color)
```
YOUR AGENT'S CORNER COACH
```

### H1
```
BETTER PROMPTS.
FEWER LOOPS.
PROOF IT WORKED.
```
Second line in accent color.

### Lede
```
Flint is a coaching layer that lives inside your AI coding workflow. It watches how you prompt, suggests what to tighten, and builds a verification habit that sticks. Direct enough to be useful. Funny enough to keep the loop human.
```

### CTA row
| Element | Copy |
|---------|------|
| Primary button | `Install Flint` → links to install.sh |
| Secondary button | `Read the docs` → links to README |
| Note (muted, mono) | `Works with Claude Code and Codex. MIT licensed.` |

### Hero image placeholder
**Description:** A stylized terminal window floating on a neon grid plane. Inside the terminal, a short coaching exchange is visible — a prompt suggestion with a glowing checkmark next to it. The grid extends to the horizon with soft cyan perspective lines. Dark background, high contrast, cybernetic aesthetic. No faces, no characters — the tool is the hero.

**Alt text:** `Terminal window on a neon grid showing an AI coaching exchange with a verification checkmark`

---

## 3. "What Flint Does" — Value Props Section

**Layout:** Section label + H2, then a 12-column card grid. Two cards on first row (7+5), three cards on second row (4+4+4). Cards have inner glow border, translucent panel background. Compact padding — this section should feel dense and scannable, not sprawling.

**Spacing:** ~80px top padding from hero. Cards at 12px gap. No card exceeds ~120px height on desktop.

### Section label (mono, uppercase, accent)
```
WHAT YOU GET
```

### H2
```
ONE COACH. THREE HABITS.
```

### Card grid

| Span | Title | Body |
|------|-------|------|
| 7 | `PROMPT SHARPENING` | `Flint turns "make it better" into constraints, acceptance criteria, and a clear definition of done. Your agent stops guessing.` |
| 5 | `VERIFICATION LOOP` | `Every task ends with proof. Flint nudges you to pick the smallest check that actually proves the behavior changed.` |
| 4 | `LIVE OBSERVATION` | `Flint watches your session and drops tips tied to what you just did — not a wall of theory, a single next move.` |
| 4 | `DIRECT TASKING` | `Ask Flint to review a prompt, tighten a spec, or suggest what to verify. It's a conversation, not a rulebook.` |
| 4 | `CODEBASE READINESS` | `Run an analysis on any repo. Flint tells you what's blocking agent autonomy and gives you a prioritized fix list.` |

---

## 4. "How It Works" — Workflow Section

**Layout:** Section label + H2, then three equal-width cards in a row (4+4+4). Each card has a step number as the title. Minimal — this section is a quick visual rhythm, not deep content.

**Spacing:** ~64px top padding. Cards same style as above.

### Section label
```
WORKFLOW
```

### H2
```
SMALL LOOPS, REPEATED.
```

### Cards

| Step | Title | Body |
|------|-------|------|
| 1 | `CLARIFY` | `Goal, constraints, risks, acceptance criteria. If you can't say what "done" looks like, Flint will ask.` |
| 2 | `VERIFY` | `Pick the smallest checks that prove behavior. No "it probably works." Prove it or loop back.` |
| 3 | `SHIP` | `Lock in a regression, keep the diff reviewable, and move on. Flint remembers what you learned.` |

---

## 5. "Game Your Progress" — Gamification Section

**Layout:** Section label + H2 + lede paragraph, then a two-column layout. Left column (span-7): a large image placeholder showing the progress UI. Right column (span-5): a stacked list of gamification elements — levels, streaks, badges — presented as compact styled items, not a full table.

**Spacing:** ~80px top padding. Image should be the visual anchor. Right-column items tight with 8px gaps.

### Section label
```
PROGRESS
```

### H2
```
TRACK THE REPS. SEE THE CHANGE.
```

### Lede
```
Flint tracks your sessions, tips, and streaks. Level up from Prompter to Commander. Unlock badges for consistency, mastery, and the occasional honest rejection. It's not gamification for its own sake — it's a mirror that shows whether your habits are actually improving.
```

### Left column image placeholder
**Description:** A dark-themed stats dashboard floating on the neon grid. Shows a level progress bar (e.g., "Level 3 — Navigator"), a streak counter with a flame icon, and a row of small badge icons — some lit in cyan, others dim/locked. Clean, minimal, data-forward. Feels like a HUD overlay, not a toy.

**Alt text:** `Flint progress dashboard showing level, streak counter, and earned badges on a dark grid background`

### Right column — highlights (styled as small inline cards or list items)

| Item | Copy |
|------|------|
| Levels | `5 ranks from Prompter to Commander. XP from sessions, tips, and streaks.` |
| Streaks | `Consecutive days build your streak. Miss a day, it resets — but your best is always recorded.` |
| Badges | `Milestone, mastery, and streak badges. Earn them by doing the work, not by clicking buttons.` |
| Honest Critic | `You get XP for rejecting tips too. Flint respects a "no" — your feedback makes coaching better.` |

---

## 6. Install CTA Banner (full-width)

**Layout:** A wide, horizontally-centered panel with a subtle inner glow. Contains a heading, a single line of body text, and a large, prominent bash command block with a copy button. This is the page's primary conversion point — it should feel like arriving at a destination, not scrolling past another section.

**Spacing:** ~80px top padding, ~48px internal padding. Command block font size ~16px (larger than the nav chip). Copy button clearly visible.

### H2
```
ONE LINE. ZERO DEPENDENCIES.
```

### Body
```
Run the installer and meet Flint. Works with Claude Code and Codex out of the box.
```

### Command block
```
$ bash <(curl -fsSL https://raw.githubusercontent.com/philippb/agent-coach/main/install.sh)
```
Button: `Copy`

### Subtext (muted, mono)
```
Or clone the repo and run bash install.sh locally. MIT licensed. Read the source first if you want — Flint would.
```

---

## 7. Footer

**Layout:** Single row, full width, top border with accent stroke. Logo left, links right. Monospace, small text. Minimal.

**Spacing:** ~48px top margin, 14px top padding.

| Left | Right |
|------|-------|
| `Flint Agent Coach — MIT` | `GitHub · Docs · Install` |

---

## Image Placeholder Summary

| Location | Filename suggestion | Description | Alt text |
|----------|-------------------|-------------|----------|
| Hero (right column) | `hero-terminal-grid.png` | Stylized terminal on a neon perspective grid showing a coaching exchange with a verification checkmark. Dark bg, cyan accents, no characters. | `Terminal window on a neon grid showing an AI coaching exchange with a verification checkmark` |
| Gamification (left column) | `progress-dashboard.png` | Dark HUD-style stats dashboard with level bar, streak flame counter, and a row of badge icons (some lit, some locked). Neon grid backdrop. | `Flint progress dashboard showing level, streak counter, and earned badges on a dark grid background` |

---

## Design Notes

- **Dark/light mode:** The existing CSS variable system handles this. All neon accents, grid lines, and panel transparencies already flip. New sections should use the same `var(--blue)`, `var(--stroke)`, `var(--panel)` tokens. No hardcoded colors.
- **Grid vibe without brand references:** The `.dotGrid` background with perspective lines evokes the cybernetic aesthetic. Copy avoids naming any franchise — the visual language does the work.
- **Install CTA prominence:** Appears three times: hero chip (first viewport), nav link (persistent), and dedicated banner (bottom of page). The banner version is the largest and most visually distinct.
- **No persona section:** Replaced by "What Flint Does" cards and the gamification section. Flint is one voice, not three.
- **Humor calibration:** "Flint would" in the install subtext. "No 'it probably works'" in verification. "Not a wall of theory, a single next move." Dry, specific, grounded in the workflow — never winking at the camera.
