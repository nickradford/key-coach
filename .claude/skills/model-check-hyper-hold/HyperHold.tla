---------------------------- MODULE HyperHold ----------------------------
(***************************************************************************)
(* The hyper-key path of Shortcut Coach: the physical key, the HID        *)
(* listener, the 30 Hz poll, the hold guide and the miss decision.        *)
(*                                                                         *)
(* Each main-thread action is one run-loop callback on the main actor, so *)
(* it is one indivisible step in the code too:                             *)
(*   HidCallback  = HyperKeyListener.handle (Signal.swift)                 *)
(*   Poll         = Coach.poll -> sampleModifiers + HoldTracker.update     *)
(*   AppActivated = Coach.appActivated, the synchronous part               *)
(*   DecideMiss   = the Task in Coach.appActivated, 150 ms later:          *)
(*                  sampleModifiers, then missedBinding (Decisions.swift)  *)
(* The other actions are the user, Tinycast and IOKit, outside the app.   *)
(*                                                                         *)
(* Assumptions: Input Monitoring is granted and the listener is open; the *)
(* hyper key choice does not change; one physical hyper key; at most one  *)
(* bound-app activation per run, and the bound app was not already in     *)
(* front; no quit or hide; lastHeld never ages past graceSeconds (that    *)
(* only makes a false miss harder to reach). DecideMiss runs after every  *)
(* HID value that was already waiting when appActivated ran: the run loop *)
(* handles those well inside the Task's 150 ms sleep.                      *)
(*                                                                         *)
(* Times in the code are compared, never counted, so the model keeps only *)
(* the order: whether the activation came at or after the press, and at   *)
(* or after HoldTracker.heldSince.                                         *)
(***************************************************************************)
EXTENDS Naturals, Sequences

CONSTANTS
    MaxPresses,  \* how many times the user presses the hyper key in one run
    DelayPolls   \* HoldTracker.delay in poll ticks (0.7 s / (1/30 s) = 21 in the app)

VARIABLES
    phys,          \* the hyper key is physically down
    flagsHyper,    \* CGEventSource flags show all four hyper modifiers (Tinycast posts them; a mouse move clears them)
    hidQ,          \* HID values IOKit delivered that the main run loop has not run yet (TRUE = down)
    isDown,        \* HyperKeyListener.isDown
    pressed,       \* HyperKeyListener.pressedAt != nil
    pressTicks,    \* polls since HyperKeyListener.pressedAt, capped at DelayPolls
    lastHeldHyper, \* Coach.lastHeld[hyperModifiers] is set (within graceSeconds)
    heldSince,     \* HoldTracker.heldSince != nil
    ticks,         \* polls since HoldTracker.heldSince, capped at DelayPolls (a poll that sets it to now counts 0)
    actSincePress, \* HoldTracker.activatedAt >= HyperKeyListener.pressedAt
    actSinceHeld,  \* HoldTracker.activatedAt >= HoldTracker.heldSince (FALSE while heldSince = nil)
    guideVisible,  \* Coach.guideVisible (the guide is on screen)
    activation,    \* "none" | "queued" (notification not yet run) | "deciding" (Task sleeping) | "done"
    hidAhead,      \* HID values that were waiting when appActivated ran and have not run yet
    flashed,       \* onMiss ran: the miss flash showed
    \* bounds and ghost variables, for the properties only
    presses,       \* presses so far
    cause,         \* "none" | "hotkey" (Tinycast switched on hyper+letter) | "click" (any other way)
    activatedThisHold,  \* the app saw a bound app activate during the current physical hold
    holdPolls,          \* polls during the current hold after the listener caught up, capped
    polledSinceRelease  \* a poll ran after the release with the listener caught up

vars == <<phys, flagsHyper, hidQ, isDown, pressed, pressTicks, lastHeldHyper, heldSince, ticks,
          actSincePress, actSinceHeld, guideVisible, activation, hidAhead, flashed, presses, cause,
          activatedThisHold, holdPolls, polledSinceRelease>>

Min(a, b) == IF a < b THEN a ELSE b

\* heldModifiers() == hyperModifiers: the listener first, else the posted flags.
Held == isDown \/ flagsHyper

Init ==
    /\ phys = FALSE /\ flagsHyper = FALSE /\ hidQ = <<>> /\ isDown = FALSE
    /\ pressed = FALSE /\ pressTicks = 0 /\ lastHeldHyper = FALSE
    /\ heldSince = FALSE /\ ticks = 0 /\ actSincePress = FALSE /\ actSinceHeld = FALSE
    /\ guideVisible = FALSE
    /\ activation = "none" /\ hidAhead = 0 /\ flashed = FALSE
    /\ presses = 0 /\ cause = "none"
    /\ activatedThisHold = FALSE /\ holdPolls = 0 /\ polledSinceRelease = FALSE

\* The app's own state, which only main-thread actions change.
app == <<isDown, pressed, pressTicks, lastHeldHyper, heldSince, ticks, actSincePress, actSinceHeld,
         guideVisible, hidAhead, flashed>>

---------------------------------------------------------------------------
\* Outside the app.

UserPressesHyper ==
    /\ ~phys /\ presses < MaxPresses
    /\ phys' = TRUE /\ flagsHyper' = TRUE
    /\ hidQ' = Append(hidQ, TRUE)
    /\ presses' = presses + 1
    /\ activatedThisHold' = FALSE /\ holdPolls' = 0
    /\ UNCHANGED <<app, activation, cause, polledSinceRelease>>

UserReleasesHyper ==
    /\ phys
    /\ phys' = FALSE /\ flagsHyper' = FALSE
    /\ hidQ' = Append(hidQ, FALSE)
    /\ polledSinceRelease' = FALSE
    /\ UNCHANGED <<app, activation, presses, cause, activatedThisHold, holdPolls>>

\* A real mouse move resets the posted modifier flags (README, Permission).
UserMovesMouse ==
    /\ flagsHyper
    /\ flagsHyper' = FALSE
    /\ UNCHANGED <<app, phys, hidQ, activation, presses, cause, activatedThisHold,
                   holdPolls, polledSinceRelease>>

\* Hyper + letter: Tinycast brings the bound app forward. Only while the key is down.
UserUsesHotkey ==
    /\ phys /\ activation = "none"
    /\ activation' = "queued" /\ cause' = "hotkey"
    /\ UNCHANGED <<app, phys, flagsHyper, hidQ, presses, activatedThisHold, holdPolls,
                   polledSinceRelease>>

\* A click, the Dock, Cmd+Tab or a launcher brings the bound app forward.
UserClicksBoundApp ==
    /\ activation = "none"
    /\ activation' = "queued" /\ cause' = "click"
    /\ UNCHANGED <<app, phys, flagsHyper, hidQ, presses, activatedThisHold, holdPolls,
                   polledSinceRelease>>

---------------------------------------------------------------------------
\* On the main thread, one callback at a time.

\* sampleModifiers(): lastHeld[hyper] is set if hyper is held now or pressedAt is set.
Sampled == lastHeldHyper \/ Held \/ pressed

\* HyperKeyListener.handle: `isDown = down`, and on a key-down `pressedAt = systemUptime`.
HidCallback ==
    /\ hidQ /= <<>>
    /\ isDown' = Head(hidQ) /\ hidQ' = Tail(hidQ)
    /\ IF Head(hidQ)
         THEN /\ pressed' = TRUE /\ pressTicks' = 0
              /\ actSincePress' = FALSE  \* the new pressedAt is later than any activation so far
         ELSE UNCHANGED <<pressed, pressTicks, actSincePress>>
    /\ hidAhead' = IF hidAhead > 0 THEN hidAhead - 1 ELSE 0
    /\ UNCHANGED <<phys, flagsHyper, lastHeldHyper, heldSince, ticks, actSinceHeld, guideVisible,
                   activation, flashed, presses, cause, activatedThisHold,
                   holdPolls, polledSinceRelease>>

\* Coach.poll: sampleModifiers(), then
\* HoldTracker.update(hyperHeld:, pressedAt: isDown ? pressedAt : nil, now:), which takes
\* since = pressedAt ?? heldSince ?? now, stores it in heldSince, and shows the guide when
\* activatedAt < since and now - since >= delay.
Poll ==
    LET pt == Min(pressTicks + 1, DelayPolls) IN
    /\ lastHeldHyper' = Sampled
    /\ pressTicks' = pt
    /\ IF Held
         THEN /\ heldSince' = TRUE
              /\ ticks' = IF isDown THEN pt
                          ELSE IF heldSince THEN Min(ticks + 1, DelayPolls) ELSE 0
              /\ actSinceHeld' = IF isDown THEN actSincePress
                                 ELSE IF heldSince THEN actSinceHeld ELSE FALSE
              /\ guideVisible' = (~actSinceHeld' /\ ticks' >= DelayPolls)
         ELSE /\ heldSince' = FALSE /\ ticks' = 0 /\ actSinceHeld' = FALSE
              /\ guideVisible' = FALSE
    /\ holdPolls' = IF phys /\ hidQ = <<>> THEN Min(holdPolls + 1, DelayPolls + 1) ELSE holdPolls
    /\ polledSinceRelease' = (polledSinceRelease \/ (~phys /\ hidQ = <<>>))
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, pressed, actSincePress, activation, hidAhead,
                   flashed, presses, cause, activatedThisHold>>

\* Coach.appActivated: sampleModifiers(), tracker.boundAppActivated(now:), then schedule the
\* decision. activatedAt = now is at or after pressedAt and heldSince, whichever are set.
AppActivated ==
    /\ activation = "queued"
    /\ lastHeldHyper' = Sampled
    /\ actSincePress' = pressed
    /\ actSinceHeld' = heldSince
    /\ hidAhead' = Len(hidQ)
    /\ activation' = "deciding"
    /\ activatedThisHold' = (activatedThisHold \/ phys)
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, pressed, pressTicks, heldSince, ticks,
                   guideVisible, flashed, presses, cause, holdPolls, polledSinceRelease>>

\* The Task, 150 ms later: sampleModifiers(), then missedBinding on lastHeld as it is now.
DecideMiss ==
    /\ activation = "deciding" /\ hidAhead = 0
    /\ lastHeldHyper' = Sampled
    /\ flashed' = ~Sampled
    /\ activation' = "done"
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, pressed, pressTicks, heldSince, ticks,
                   actSincePress, actSinceHeld, guideVisible, hidAhead, presses, cause,
                   activatedThisHold, holdPolls, polledSinceRelease>>

Next ==
    \/ UserPressesHyper \/ UserReleasesHyper \/ UserMovesMouse
    \/ UserUsesHotkey \/ UserClicksBoundApp
    \/ HidCallback \/ Poll \/ AppActivated \/ DecideMiss

Spec == Init /\ [][Next]_vars

---------------------------------------------------------------------------
\* Properties.

\* A switch made with the hyper hotkey never flashes a miss.
HotkeyNeverFlashes == cause = "hotkey" => ~flashed

\* Once the key is up and a poll has seen that, the guide is hidden.
GuideHidesAfterRelease ==
    (~phys /\ hidQ = <<>> /\ polledSinceRelease) => ~guideVisible

\* Holding the key past the delay shows the guide, unless a bound app activated during this hold
\* (shortcut-coach-design.md at 07b4a20, "The hold guide": "no bound app was activated in that time").
GuideShowsOnLongHold ==
    (phys /\ ~activatedThisHold /\ holdPolls > DelayPolls) => guideVisible

TypeOK ==
    /\ phys \in BOOLEAN /\ flagsHyper \in BOOLEAN /\ isDown \in BOOLEAN
    /\ hidQ \in Seq(BOOLEAN) /\ Len(hidQ) <= 2 * MaxPresses
    /\ pressed \in BOOLEAN /\ actSincePress \in BOOLEAN /\ actSinceHeld \in BOOLEAN
    /\ ticks \in 0..DelayPolls /\ pressTicks \in 0..DelayPolls /\ holdPolls \in 0..(DelayPolls + 1)
    /\ hidAhead \in 0..Len(hidQ)
    /\ activation \in {"none", "queued", "deciding", "done"}
    /\ cause \in {"none", "hotkey", "click"}
=============================================================================
