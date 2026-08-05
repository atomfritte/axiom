# Your data

Everything stays on the device. No account, no cloud, no telemetry — and an export that stays readable without AXIOM.

## Where it sits

In a SQLite file in the app's private storage. Other apps cannot reach it — that is Android's doing.

**On the phone the file is encrypted.** Without the key it cannot be read, not even as a copy. The key lives in the device keystore, in secured hardware, and cannot leave it — it travels into no backup and onto no other device.

What that does **not** protect against: someone holding your unlocked device who opens the app. For them the keystore decrypts willingly. A screen lock is not a formality; it is the first line of defence.

**On the desktop the file sits in plain text.** Linux has no keystore to put a key in, and a key file next to the database would be a prop. What is there is as protected as your user account. The app tells you which case applies — under *System → Data*.

**Exports** are encrypted on both, with a passphrase you choose.

If the key is lost — cleared app data, a restored backup, a new device — the database can no longer be read. AXIOM then creates a fresh one and **says so** on that same screen, rather than sitting there empty without comment.

Everything is an **event**, and events are only appended, never changed and never deleted. A correction is a new event. Two things follow from that: the entire state can be recalculated from the stream at any time, and nothing disappears quietly.

## What goes in

Check-ins, captures, tasks, anchors, focus blocks, stimulation slots, intercepted impulses, incidents — and, if granted, sleep windows and daily steps from Health Connect.

![Health Connect is optional and reads two quantities only. On the desktop the question does not arise.](img/health.webp)

Health Connect is **read only**, never written: sleep times and steps per day. No heart rate, no weight, no location. The permission can be changed at any time in both directions, under *System → Data sources*.

There is no location access at all. The "place" on a task is a name that you or a device routine set.

## How it gets out

Under *System → Data*:

- **Export** writes every event into a `.axiom` file, encrypted with a passphrase of at least eight characters. Inside it is NDJSON — with the passphrase readable without AXIOM too. Otherwise it would not be data ownership.
- **Import** plays missing events in. Existing ones stay untouched and the import is repeatable. A **dry run** shows beforehand what would happen.

That is how two devices align: both import the other's file, and afterwards both have everything. Because events are immutable, nothing can collide.

> The passphrase is stored nowhere. If it is lost, the file is unusable — that is the price of nobody else being able to read it.

## The active window

Also under *System → Data*, **off** by default. Switched on, it logs doses taken with the onset and duration you observe.

AXIOM only logs. It names no dose, suggests no time to take anything, and rates no effect. Everything to do with treatment belongs with your doctor.

Where AXIOM sends data by itself: nowhere. Why that promise takes a narrower form once expert mode exists is in [At the desk: expert mode](kapitel:11).
