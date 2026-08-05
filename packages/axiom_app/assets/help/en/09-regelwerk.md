# The rulebook

Every rule is readable: condition, action, reasoning, limits, and what it has done over the last seven days. Under *System → Rulebook*.

![System: the meta-work budget on top, the state of calibration below. The rulebook is one tap further.](img/system.webp)

## What a rule shows

- **Reasoning** — why it exists. Mandatory; without it the rule is not loaded at all.
- **Condition** — the complete if-tree in plain language.
- **Limits** — priority, minimum interval, maximum per day, backoff.
- **Last 7 days** — how often it fired, how often it was displaced, how often followed, deferred, rejected.
- **Currently inactive** — why it does not apply right now: condition not met, cooldown running, daily limit reached, quiet hours, or data too thin.

Tags along the edge: **SHADOW** means the rule runs silently. **UNCALIBRATED** means it checks values whose formula weights are still estimates.

## The global limits

| Limit | Value |
|---|---|
| Interventions per day | 12 |
| Notifications per hour | 2 |
| Quiet hours | 23:00–06:30 |
| Minimum confidence | 0.40 |

Without these caps, individually sensible rules add up to a flood of notifications — the most common reason apps like this get muted after three weeks. And a muted app is a deleted app with extra steps.

## Changing

The editor only offers what the engine understands, and it evaluates every condition against the state of right now: while typing you see whether the rule would apply and which part of it fails.

Two things are not negotiable:

1. **Reasoning and minimum interval are mandatory.** Otherwise the editor does not save.
2. **Every saved rule runs seven days in silence**, a changed one included. Changed means new, and it gets judged on days still to come.

Changes sit as an overlay in the database; the shipped files stay untouched. The code icon copies any rule as YAML — in exactly the form that can go back into `rules/` on the desktop. Only there is it under version control.

## Switching off

One switch per rule. Switched off it is kept, but not evaluated.

Switching off always works — even when the meta-work budget is used up and the editor is therefore closed. Letting a misfiring rule run until tomorrow would be damage control by doing nothing.

Why that budget exists and when the editor opens again is in [Review and calibration](kapitel:10).
