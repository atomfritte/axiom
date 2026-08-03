<img src="assets/brand/axiom-wordmark.svg" alt="AXIOM" width="320">

***English** · [Deutsch](README.de.md)*

A deterministic, local-first rule engine for self-regulation.
An exocortex for a highly compensated ADHD profile.

**Private. One user. One device. Not a product.**

---

> ⚠️ **Not a medical device.** AXIOM is not diagnostics, not therapy, and not a substitute for
> medical or psychotherapeutic treatment. It measures self-reported and device-measured states
> and applies **self-authored** rules to them. Nothing more.

---

## The idea in three sentences

A highly compensated ADHD profile does not fail for lack of structure. It fails because that
structure has to be regenerated in the head every single day. AXIOM takes over the generation:
measure state, apply rules you wrote yourself, output **exactly one** next action — with the
reasoning and the rule ID that produced it.

The measure of success is not "more done". It is **the same output at lower cognitive cost**.

## What makes it different

| A conventional app | AXIOM |
|---|---|
| Asks *what do you want to do?* | Asks *what state are you in?* |
| Models `priority` | Models `activation_energy` against available capacity |
| Shows a list | Shows **one** action + `rule_id` + reasoning |
| Rewards usage | **Caps** usage (meta-guard) |

### One action, never a list

This is the part that most often gets misread as a limitation. It is the point.

Presenting five options requires choosing between them, and choosing is exactly the executive
function that is scarce in this profile. A list does not reduce load — it relocates it. So the
main screen shows one thing, and next to it the rule that put it there.

### Every output is auditable

There is no model, no score without a visible formula, and no LLM in the decision loop. Every
recommendation carries its `rule_id`, and every rule is a readable YAML file under version
control. `evaluate(state, ruleset) → decision` is a pure function: same input, same output,
always.

That is not a purity exercise. A systemizing mind discards a system it cannot audit — and a
system that gets discarded collects no data.

## The four laws

Any conflict is resolved in favour of these, even against an explicit feature request.

| | Law | In practice |
|---|---|---|
| **G1** | **Offload, don't demand** | No screen that forces thinking. Capture < 3 s, check-in < 15 s, daily review < 2 min. |
| **G2** | **Explainable, not intelligent** | Every output names its `rule_id` and its reasoning. No AI in the decision loop. |
| **G3** | **Channel, don't suppress** | Stimulation need gets a budget, never a moral. No guilt language, no bans — only latency, visibility, alternatives. |
| **G4** | **Self-limiting** | AXIOM caps its own usage time and rations its own configuration. |

G4 is the most important one here. The main risk to this project is not technical failure but
that building the system becomes the procrastination. Which is why the meta-guard was built
first, not last.

## Documentation

| Document | Contents |
|---|---|
| [00-KONZEPT](docs/00-KONZEPT.md) | What AXIOM is, the four laws, all 13 modules |
| [01-PROFIL-DEFIZITE](docs/01-PROFIL-DEFIZITE.md) | Target profile D1–D12 — the basis for everything |
| [02-ARCHITEKTUR](docs/02-ARCHITEKTUR.md) | Layers, ports, evaluation cycle |
| [03-DATENMODELL](docs/03-DATENMODELL.md) | Events, state vector, task, formulas |
| [04-REGELWERK](docs/04-REGELWERK.md) | Rule DSL, semantics, conflict resolution |
| [05-ROADMAP](docs/05-ROADMAP.md) | Stages S1–S4 with stop criteria |
| [06-METRIKEN](docs/06-METRIKEN.md) | Success measurement, baseline protocol |
| [07-RISIKEN](docs/07-RISIKEN.md) | What goes wrong — R1 is the decisive one |
| [08-GERAET-S25U](docs/08-GERAET-S25U.md) | S Pen, Health Connect, Android pitfalls |
| [ADR](docs/adr/) | Architecture decisions, with reasoning |
| [BACKLOG](docs/BACKLOG.md) | Ideas deliberately *not* built yet |

The documentation is in German — it predates the decision to publish, and translating it would
cost more than it returns. The code, identifiers and this README are English.
For Claude Code: [CLAUDE.md](CLAUDE.md).

## Stack

Flutter 3.44 / Dart 3.12 · SQLite · YAML rulebook under git
Targets: Android (Galaxy S25 Ultra, primary) and Linux desktop (companion)

## Layout

```
packages/axiom_core   pure Dart — domain + state engine + rule engine   ← the heart
packages/axiom_data   SQLite, YAML loader, export
packages/axiom_app    Flutter UI, notifications, widgets, Health Connect
rules/core            shipped rules (versioned)
rules/personal        personal rules (git-ignored)
tools/                validator, layering check, calibration
```

Dependencies point **inwards, always**. `axiom_core` has no Flutter, no platform and no I/O
dependency — no `DateTime.now()`, no `Random()`, both injected as ports. Without that, rules are
not deterministically testable, and determinism is what G2 rests on.
`dart run tools/bin/check_layering.dart .` fails the build on violations.

## Development

```bash
# Checks — all of these must be green
dart run tools/bin/validate_rules.dart rules
dart run tools/bin/check_layering.dart .
(cd packages/axiom_core && dart analyze && dart test)
(cd packages/axiom_data && dart analyze && dart test)
(cd packages/axiom_app  && flutter analyze && flutter test)

# Mirror the rulebook into app assets — before every app build
dart run tools/bin/sync_rules.dart

# Run
(cd packages/axiom_app && flutter run -d linux)
(cd packages/axiom_app && flutter run -d <device>)     # adb devices
```

## Status

**S1 through S4 are in place.** The Android APK and the Linux desktop build and run.

| | |
|---|---|
| Tests | 451 green (215 core · 88 data · 148 app) |
| Analyzer | clean across all packages |
| Rulebook | 17 rules valid, 16 active — 8 of them **uncalibrated** |
| Release APK | built, **without the INTERNET permission** — verified in the package |

**Stage 1** — capture (< 3 s), check-in, capacity line, state view with derivation, rule
inspector, meta-guard, onboarding, home screen widget, quick settings tile, exact alarms, app
shortcuts, share target.

**Stage 2** — time anchors with backward chaining (M3), atomizer (M2), body signals (M7),
evening cutoff and sleep logging (M8), review with an enforced time cap (M11).

**Stage 3** — focus governor (M4), stimulation budget with the slot as currency (M5), impulse
brake with a self-written checklist (M6), load monitor with real consequences up to maintenance
mode (M9).

**Stage 4** — signal log with capture and hindsight kept apart (M10), active-window log (M13,
opt-in), encrypted data sync by file instead of by server.

**Platform integration** — live update of the running focus slot in the status bar chip, on the
lock screen and in Samsung's Now bar (Android 16, `ProgressStyle` + `requestPromotedOngoing`);
Health Connect for sleep windows and daily steps, imported idempotently; Direct Share as a fixed
target in the share sheet.

### The rule editor

Rules can be written on the device (*System → Rulebook*). Not a text box: the editor knows the
engine's vocabulary, so it only offers what the engine can resolve — and it evaluates every
condition against the **current** state while you type. Each line shows what the value is right
now and whether that part holds.

Two guardrails are enforced in code, not suggested:

- Every saved rule runs as `log_only` for **seven days**, whatever severity was chosen. A rule
  that goes live the day it is written gets judged on the day you were convinced it was right.
- `rationale` and `cooldown` are required. Without reasoning an output is not auditable (G2);
  without a cooldown you get a flood of notifications — the most common way apps like this die.

Edits live as an overlay in the database, never in `rules/core/`. `ruleToYaml` returns a rule in
exactly the form `rules/` uses, so anything written on the phone can be copied back into version
control. A round-trip test keeps that honest.

### Why there is no cloud

`INTERNET` is not declared in the manifest. Not "we don't send anything" — the permission is
absent, so at the operating system level nothing *can* leave the device, regardless of any bug,
any transitive dependency, any oversight. That is considerably stronger than an assurance in
code, and it is verified in the built APK by a test.

Sync exists nonetheless, as an encrypted file: events are immutable, so their union is
conflict-free and a repeated import is idempotent. Two devices converge without a server.

### Two languages

German is the source, English is the translation — switchable under *System → Display*. The
notable part: **the German sentence is the key**.

```dart
Text(context.t('Nichts in Reichweite'))
```

That keeps the wording legible where it was chosen. Which matters here more than usual:
"Nothing in reach" is a deliberate choice against "You have 14 open tasks", and that choice
should not disappear behind an identifier like `now.emptyTitle`.

Three layers are covered:

| Layer | Where | How |
|---|---|---|
| Interface | `lib/i18n/en.dart` | German sentence → English sentence |
| Core | `Phrase('{0} min über …', [n])` | source and values kept apart, so numbers never have to be recovered from a finished sentence |
| Rulebook | `title_en`, `rationale_en` in the YAML | rules are data; so are their translations |

`i18n_test.dart` pins down three things: **every** translatable text has an English version, the
placeholders match on both sides, and the tone holds — no guilt language, no exclamation marks.
That last one is the actual reason for the test. A translation can turn a measurement into a
verdict without anyone noticing.

### Ways into the app

Between the thought and the note there are a few seconds. What is not held in that time is gone
(D9) — so there is not one route but seven. They are listed in the app under *System → Capture*,
with setup instructions.

| Route | Friction | How |
|---|---|---|
| **Ongoing notification** | minimal | type straight into the notification, no unlock (`RemoteInput`) |
| Quick settings tile | very low | one tap from any app |
| Home screen widget | low | next action + capacity, tap goes to the input field |
| App shortcut | low | long press on the icon |
| Share from other apps | low | `ACTION_SEND`, plus Direct Share |
| S Pen | low | `ACTION_CREATE_NOTE` (Android 14+), can also be bound to Air Actions |
| Voice | low | `actions.intent.CREATE_NOTE` for Assistant, Bixby routine |

Two platform limits, named explicitly rather than worked around:

- **Android has no lock screen widgets** — removed in 5.0. The remaining route to permanent
  visibility while locked is the ongoing notification (`VISIBILITY_PUBLIC`).
- **Samsung Notes has no public interface.** Screen-off memos stay there. The official pen route
  is `ACTION_CREATE_NOTE`.

### Calibration

The formula weights in `rules/core/weights.yaml` are estimated, not measured. Eight active rules
test derived values and can therefore be wrong. They run anyway — a deliberate decision. The
system inspector marks them **UNCALIBRATED**.

**Where to see the state:** in the app under *System → Calibration*. Three conditions with
progress, and once all of them are met, the full procedure with copyable commands.

| Condition | Needed | Why |
|---|---|---|
| Days | 14 | Anything shorter misses a full weekly rhythm |
| Readings | 20 check-ins | Below that the circadian profile does not hold |
| Nights | 7 sleep entries | For the sleep–capacity coupling |

**Time alone is not enough.** Fourteen days with five check-ins would calibrate the weights on
noise — worse than an honest estimate. So all three are checked and shown separately.

```bash
adb exec-out run-as de.axiom.axiom_app cat files/axiom.db > axiom.db
dart run tools/bin/calibrate.dart axiom.db      # writes nothing, only proposes
# Review the proposals in the weekly review, then enter them in
# rules/core/weights.yaml and set calibration.status to calibrated:
dart run tools/bin/sync_rules.dart
```

## What it looks like

<p>
  <img src="packages/axiom_app/test/screenshots/04-jetzt-aufgaben.png" width="180" alt="Now — one action with its rule">
  <img src="packages/axiom_app/test/screenshots/05-zustand.png" width="180" alt="State — six readings with their derivation">
  <img src="packages/axiom_app/test/screenshots/10-zerlegen.png" width="180" alt="Split — turning a task into a first step">
  <img src="packages/axiom_app/test/screenshots/12-fokus.png" width="180" alt="Focus — a running block">
</p>
<p>
  <img src="packages/axiom_app/test/screenshots/02-onboarding-linie.png" width="180" alt="Onboarding — the capacity line explained">
  <img src="packages/axiom_app/test/screenshots/06-system.png" width="180" alt="System — the rule inspector">
  <img src="packages/axiom_app/test/screenshots/14-bremse.png" width="180" alt="Brake — a waiting period with your own questions">
  <img src="packages/axiom_app/test/screenshots/08-jetzt-hell.png" width="180" alt="The same screen in light mode">
</p>

Left to right: **one action** with the rule that produced it · the **state** behind it, every
number expandable into its formula · **splitting** something out of reach into a first step ·
a **running focus block**. Below: the capacity line explained during onboarding · the **rule
inspector** · the **impulse brake** with your own questions · the same main screen in light mode.

These are not marketing shots. They are the golden files from
`packages/axiom_app/test/screenshots/`, produced by the test suite — which means they cannot
drift from the code without a test going red.

## The mark

A scale with one threshold set on it. Left, solid: what is in reach. Right, dimmed: what is
beyond today. That is the core image of the app — and it is what an axiom is: a boundary you
set, not one you derive.

No brain, no lightbulb, no checkmark, no finish flag. The mark comes from the world of measuring
instruments, not from the visual language of self-optimisation apps.

Sources in `assets/brand/`. The Android icons are generated from them:

```bash
tools/bin/make-icons.sh
```

## Licence

None yet. This is a personal project published for reading, not a package to depend on. If you
want to use something from it, ask.
