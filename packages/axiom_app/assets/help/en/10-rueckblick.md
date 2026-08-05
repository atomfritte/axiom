# Review and calibration

Four reviews with a hard time cap — and the procedure that turns estimated formula weights into your own.

## The four scopes

| Scope | Cap | What it is about |
|---|---|---|
| Day | 2 min | What was left undone that could not be left undone |
| Week | 15 min | Deviations, rules that annoyed, at most three intentions |
| Month | 30 min | What did I quietly say goodbye to |
| Quarter | 60 min | Has the load gone down? What can go? |

The cap runs visibly and closes the review by itself at the end. That is not convenience: a review without a limit becomes an avoidance activity of its own.

![The weekly review: metrics with their consequence, each one unfolding into how it was calculated.](img/review.webp)

Every metric unfolds to show how it was calculated. Values that stand out get a dot and a sentence about what follows from them — not a grade.

For the rulebook, verdicts appear: **RETIRE** for a rule that only ever gets rejected, **TOO NARROW** for one that never fires, **CONFLICT** for two that keep displacing each other. Changes belong in the weekly review and upward; in the daily one they are only listed.

## Why the time is capped

AXIOM counts the time you spend in the system instead of in your life. Capture does not count towards it — configuration, analysis and browsing do. The budget is twelve minutes a day.

Once it is used up, the rule editor is closed for today; tomorrow it is open again. Capturing, working, looking things up and switching a rule off stay available the whole time.

> This is not a punishment, it is the point. Building a system is always more stimulating than the task it was built for.

## Calibrating

Once the three baseline conditions are met, the main view says so by itself. From then on the formula weights can come from your measurements instead of from estimates — that is the point at which the recommendations become dependable.

The procedure is in the app under *System → Calibration*, with commands to tap and copy:

1. Pull the database onto the desktop and run `calibrate.dart` over it. The tool writes nothing — it only proposes.
2. Go through the proposals in the next weekly review. Do not adopt them blindly; every value should stay explainable.
3. Enter the values in `weights.yaml` and set `calibration.status` to `calibrated`.
4. Mirror the rulebook and rebuild. After that the **UNCALIBRATED** tags disappear.

The detour via the desktop is deliberate. A calibration you can nudge on your phone in thirty seconds is not one.
