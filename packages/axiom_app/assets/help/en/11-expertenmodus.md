# At the desk: expert mode

Write rules, see the task list with every field, read the event stream — on the big screen, against the real data on the phone.

For that AXIOM starts a small server on the phone. The desktop opens it over the same network. Nothing goes to the internet and nothing goes through somebody else's service.

## Switching it on

*System → Expert mode*, then *Start server*. Three things then stand on the screen:

- the **address**, usually `axiom.local` with a port, plus an IP address as a fallback
- a **PIN**, six digits, valid only for this run
- the **fingerprint** of the certificate

## The two comparisons

The browser will warn once, because the certificate is self-signed — no outside authority vouches for it. Instead of clicking the warning away: compare the fingerprint with the one the browser lists under "show certificate". If both match, you are talking to this phone and to nothing in between.

After the PIN a second number appears, on the phone and in the browser. The protection is not in the confirmation but in the comparison: if somebody else is asking at the same moment, their number is on the phone and not on the screen in front of you. That is why "doesn't match" sits next to "matches" as an equal — declining costs nothing but a second attempt.

## What switches it off again

Five wrong PINs. Thirty minutes without a request. The button in the app or on the notification. And closing the app in any case.

There is no autostart at boot. Optionally the server comes up when you open AXIOM — sign-in, the persistent display and the shutdown after idle time all stay in place even then.

## What works there

- **Tasks as a list**, every field, directly editable. The app deliberately shows one action; planning is something other than deciding in the moment.
- **The rulebook as YAML.** Invalid is rejected, not skipped. The same promise holds: seven days in silence.
- **State and event stream.** Read-only — events are immutable.

## What it costs

Because this mode exists, AXIOM holds the network permission. The earlier guarantee that data cannot leave the device at the operating system level no longer applies. A narrower, tested one takes its place: **AXIOM listens, but never calls out.** There is no network client anywhere in the code, and a test holds that in place.

So that `axiom.local` resolves, AXIOM answers name queries on the local network. That packet contains only the name and IP of this device, and it only runs while the server runs.
