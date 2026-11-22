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
(*   DecideMiss   = the Task in Coach.appActivated, 150 ms later,          *)
(*                  calling missedBinding (Decisions.swift)                *)
(* The other actions are the user, Tinycast and IOKit, outside the app.   *)
(*                                                                         *)
(* Assumptions: Input Monitoring is granted and the listener is open; the *)
(* hyper key choice does not change; one physical hyper key; at most one  *)
(* bound-app activation per run, and the bound app was not already in     *)
(* front; no quit or hide; lastHeld never ages past graceSeconds (that    *)
(* only makes a false miss harder to reach).                               *)
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
    lastHeldHyper, \* Coach.lastHeld[hyperModifiers] is set (within graceSeconds)
    heldSince,     \* HoldTracker.heldSince != nil
    ticks,         \* polls since HoldTracker.heldSince, capped at DelayPolls
    blocked,       \* HoldTracker.blocked
    guideVisible,  \* Coach.guideVisible (the guide is on screen)
    activation,    \* "none" | "queued" (notification not yet run) | "deciding" (Task sleeping) | "done"
    snapshot,      \* MissInput.lastHeld[hyper] as captured in appActivated
    flashed,       \* onMiss ran: the miss flash showed
    \* bounds and ghost variables, for the properties only
    presses,       \* presses so far
    cause,         \* "none" | "hotkey" (Tinycast switched on hyper+letter) | "click" (any other way)
    activatedThisHold,  \* the app saw a bound app activate during the current physical hold
    holdPolls,          \* polls during the current hold after the listener caught up, capped
    polledSinceRelease  \* a poll ran after the release with the listener caught up

vars == <<phys, flagsHyper, hidQ, isDown, lastHeldHyper, heldSince, ticks, blocked,
          guideVisible, activation, snapshot, flashed, presses, cause,
          activatedThisHold, holdPolls, polledSinceRelease>>

Min(a, b) == IF a < b THEN a ELSE b

\* heldModifiers() == hyperModifiers: the listener first, else the posted flags.
Held == isDown \/ flagsHyper

Init ==
    /\ phys = FALSE /\ flagsHyper = FALSE /\ hidQ = <<>> /\ isDown = FALSE
    /\ lastHeldHyper = FALSE
    /\ heldSince = FALSE /\ ticks = 0 /\ blocked = FALSE /\ guideVisible = FALSE
    /\ activation = "none" /\ snapshot = FALSE /\ flashed = FALSE
    /\ presses = 0 /\ cause = "none"
    /\ activatedThisHold = FALSE /\ holdPolls = 0 /\ polledSinceRelease = FALSE

---------------------------------------------------------------------------
\* Outside the app.

UserPressesHyper ==
    /\ ~phys /\ presses < MaxPresses
    /\ phys' = TRUE /\ flagsHyper' = TRUE
    /\ hidQ' = Append(hidQ, TRUE)
    /\ presses' = presses + 1
    /\ activatedThisHold' = FALSE /\ holdPolls' = 0
    /\ UNCHANGED <<isDown, lastHeldHyper, heldSince, ticks, blocked, guideVisible,
                   activation, snapshot, flashed, cause, polledSinceRelease>>

UserReleasesHyper ==
    /\ phys
    /\ phys' = FALSE /\ flagsHyper' = FALSE
    /\ hidQ' = Append(hidQ, FALSE)
    /\ polledSinceRelease' = FALSE
    /\ UNCHANGED <<isDown, lastHeldHyper, heldSince, ticks, blocked, guideVisible,
                   activation, snapshot, flashed, presses, cause, activatedThisHold, holdPolls>>

\* A real mouse move resets the posted modifier flags (README, Permission).
UserMovesMouse ==
    /\ flagsHyper
    /\ flagsHyper' = FALSE
    /\ UNCHANGED <<phys, hidQ, isDown, lastHeldHyper, heldSince, ticks, blocked, guideVisible,
                   activation, snapshot, flashed, presses, cause, activatedThisHold,
                   holdPolls, polledSinceRelease>>

\* Hyper + letter: Tinycast brings the bound app forward. Only while the key is down.
UserUsesHotkey ==
    /\ phys /\ activation = "none"
    /\ activation' = "queued" /\ cause' = "hotkey"
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, lastHeldHyper, heldSince, ticks, blocked,
                   guideVisible, snapshot, flashed, presses, activatedThisHold, holdPolls,
                   polledSinceRelease>>

\* A click, the Dock, Cmd+Tab or a launcher brings the bound app forward.
UserClicksBoundApp ==
    /\ activation = "none"
    /\ activation' = "queued" /\ cause' = "click"
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, lastHeldHyper, heldSince, ticks, blocked,
                   guideVisible, snapshot, flashed, presses, activatedThisHold, holdPolls,
                   polledSinceRelease>>

---------------------------------------------------------------------------
\* On the main thread, one callback at a time.

\* HyperKeyListener.handle: `if key == hyperKey { isDown = down }`.
HidCallback ==
    /\ hidQ /= <<>>
    /\ isDown' = Head(hidQ) /\ hidQ' = Tail(hidQ)
    /\ UNCHANGED <<phys, flagsHyper, lastHeldHyper, heldSince, ticks, blocked, guideVisible,
                   activation, snapshot, flashed, presses, cause, activatedThisHold,
                   holdPolls, polledSinceRelease>>

\* Coach.poll: sampleModifiers(), then HoldTracker.update(hyperHeld:now:).
Poll ==
    /\ lastHeldHyper' = (lastHeldHyper \/ Held)
    /\ IF Held
         THEN /\ heldSince' = TRUE
              /\ ticks' = IF heldSince THEN Min(ticks + 1, DelayPolls) ELSE 0
              /\ guideVisible' = (~blocked /\ ticks' >= DelayPolls)
              /\ UNCHANGED blocked
         ELSE /\ heldSince' = FALSE /\ ticks' = 0 /\ blocked' = FALSE
              /\ guideVisible' = FALSE
    /\ holdPolls' = IF phys /\ hidQ = <<>> THEN Min(holdPolls + 1, DelayPolls + 1) ELSE holdPolls
    /\ polledSinceRelease' = (polledSinceRelease \/ (~phys /\ hidQ = <<>>))
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, activation, snapshot, flashed, presses,
                   cause, activatedThisHold>>

\* Coach.appActivated: sampleModifiers(), build MissInput with lastHeld as it is now,
\* tracker.boundAppActivated(), then schedule the decision.
AppActivated ==
    /\ activation = "queued"
    /\ lastHeldHyper' = (lastHeldHyper \/ Held)
    /\ snapshot' = (lastHeldHyper \/ Held)
    /\ blocked' = TRUE
    /\ activation' = "deciding"
    /\ activatedThisHold' = (activatedThisHold \/ phys)
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, heldSince, ticks, guideVisible, flashed,
                   presses, cause, holdPolls, polledSinceRelease>>

\* The Task, 150 ms later: missedBinding on the captured input.
DecideMiss ==
    /\ activation = "deciding"
    /\ flashed' = ~snapshot
    /\ activation' = "done"
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, lastHeldHyper, heldSince, ticks, blocked,
                   guideVisible, snapshot, presses, cause, activatedThisHold, holdPolls,
                   polledSinceRelease>>

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
    /\ ticks \in 0..DelayPolls /\ holdPolls \in 0..(DelayPolls + 1)
    /\ activation \in {"none", "queued", "deciding", "done"}
    /\ cause \in {"none", "hotkey", "click"}
=============================================================================
