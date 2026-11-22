# Hold guide

While the user holds the hyper key (Caps Lock via Tinycast, or the key chosen in onboarding) for 0.7 s, an island under the notch lists every installed hyper-bound app as an icon over a keycap, plus `Hide others` when that system action is on hyper, and a black letter badge sits on each visible window of a bound app. Releasing hides the island and the badges.

## Sub-features

- `guide-show` holding hyper 0.7 s shows the strip island and the badges.
- `guide-strip` one cell per installed hyper-bound app, sorted by key, plus `Hide others`.
- `guide-badges` one badge window (116x116 pt) per visible window of a running bound app.
- `guide-hide` releasing hyper hides the island and badges.
- `guide-blocked` a bound app activating during the hold keeps the guide hidden until hyper is released.
- `guide-physical-key` with Input Monitoring, the physical key keeps the guide up even when a mouse move resets the posted flags.

## How to get to it (user POV)

- Hold Caps Lock (or the chosen hyper key) for a moment, then release.
- The onboarding `Try it` step asks for the same hold and ticks off when the guide appears.

## Driving it with coach.sh

Preconditions:

- Baseline preconditions hold, including Accessibility for the shell.
- No island on screen (wait 2 s after a `miss`).

- **Hold hyper.** Run `coach.sh guide` (3 s hold). `steps.txt` records `guide on screen after ~800 ms`. `windows-during.txt` shows the strip panel `onscreen=true` at `y=0` (about 447x158 with six cells) and one `onscreen=true` 116x116 panel per visible bound-app window.
- **Strip content.** Read `guide.png`. It shows one icon over a keycap per bound app (here `C D O R Z`) and `Hide others` over `F`.
- **Release.** Same run. `windows-after.txt`, 1 s after release, shows every `layer=2147483631` panel `onscreen=false`.
- **Too short.** Run `coach.sh guide 0.3`. `steps.txt` has no `guide on screen` line and `windows-during.txt` has no `onscreen=true` panel.
- **Proof.** Keep the `guide` evidence dir and read `guide.png`.

## Gotchas

- `probe hyper` posts modifier flags, the path Tinycast's hyper takes. It does not reach IOHID, so it never exercises `HyperKeyListener` (the physical key). `guide-physical-key` stays unverified until a human holds Caps Lock and moves the mouse; report it as such.
- Posting needs Accessibility for the shell's responsible app. Without it `probe` exits 3 and `guide` fails; ask the user to grant it, never grant it yourself.
- The first run of a freshly compiled probe can take about a second to start (system policy scan). `guide` polls for the panel instead of sleeping a fixed time; do not replace that with a fixed sleep.
- While hyper is posted, any key the user types is a hyper chord. Keep holds short.
- Badges appear only for running bound apps with on-screen windows; an empty badge list is not a failure when none are running.
- The strip shows only bindings whose app is installed (`urlForApplication` finds it).
- Assert on the strip panel (about 447x158 at `y=0`) and the 116x116 badges. The flash panel (about 296x118) can also read `onscreen=true` during a guide run when any bound app came forward shortly before, including focus changes the user makes; that is not a guide failure.
