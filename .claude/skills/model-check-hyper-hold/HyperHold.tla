---------------------------- MODULE HyperHold ----------------------------
(***************************************************************************)
(* The hyper-key path of Shortcut Coach: the physical key, the HID        *)
(* listener, the 30 Hz poll, the hold guide and the miss decision.        *)
(* A hit is the bound app's own key: the letter's HID key-down, kept with *)
(* its own timestamp and read when the decision runs.                     *)
(*                                                                         *)
(* Each main-thread action is one run-loop callback on the main actor, so *)
(* it is one indivisible step in the code too:                             *)
(*   HidCallback  = HyperKeyListener.handle / handleKeyDown (Signal.swift) *)
(*   Poll         = Coach.poll -> sampleModifiers + HoldTracker.update     *)
(*   AppActivated = Coach.appActivated, the synchronous part               *)
(*   DecideMiss   = the Task in Coach.appActivated, 150 ms later:          *)
(*                  missedBinding on lastPress, lastKeyDownAt, lastClick   *)
(* The other actions are the user, Tinycast and IOKit, outside the app.   *)
(*                                                                         *)
(* Assumptions: Input Monitoring is granted and the listener is open; the *)
(* hyper key choice does not change; one physical hyper key; at most one  *)
(* bound-app activation per run, and the bound app was not already in     *)
(* front; no quit or hide; no input ages past graceSeconds. DecideMiss    *)
(* runs after every HID value that was already waiting when appActivated  *)
(* ran, and after the click monitor's callback for a click before it: the *)
(* run loop handles those well inside the Task's 150 ms sleep. The hyper  *)
(* key alone is not a key-down (Caps Lock is a modifier event).           *)
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
    hidQ,          \* HID values IOKit delivered that the main run loop has not run yet: "down" / "up" (hyper), "letter"
    isDown,        \* HyperKeyListener.isDown
    pressed,       \* HyperKeyListener.pressedAt != nil
    pressTicks,    \* polls since HyperKeyListener.pressedAt, capped at DelayPolls
    pressBound,    \* HyperKeyListener.lastPress is the bound app's key, stamped at or before the activation
    heldSince,     \* HoldTracker.heldSince != nil
    ticks,         \* polls since HoldTracker.heldSince, capped at DelayPolls (a poll that sets it to now counts 0)
    actSincePress, \* HoldTracker.activatedAt >= HyperKeyListener.pressedAt
    actSinceHeld,  \* HoldTracker.activatedAt >= HoldTracker.heldSince (FALSE while heldSince = nil)
    guideVisible,  \* Coach.guideVisible (the guide is on screen)
    activation,    \* "none" | "queued" (notification not yet run) | "deciding" (Task sleeping) | "done"
    hidAhead,      \* HID values that were waiting when appActivated ran and have not run yet
    flashed,       \* onMiss ran: the miss flash showed
    keyBefore,     \* a key-down reached the HID system state before the activation (lastKeyDownAt reads it)
    clickBefore,   \* a click landed on the Dock or the bound app before the activation (Coach.lastClick)
    \* bounds and ghost variables, for the properties only
    presses,       \* presses so far
    cause,         \* "none" | "hotkey" (Tinycast switched on hyper+letter) | "click" (the user, another way)
                   \* | "system" (a link or notification: no key or click of the user's)
    activatedThisHold,  \* the app saw a bound app activate during the current physical hold
    holdPolls,          \* polls during the current hold after the listener caught up, capped
    polledSinceRelease, \* a poll ran after the release with the listener caught up
    polledSinceActivation  \* a poll ran after AppActivated with the listener caught up

vars == <<phys, flagsHyper, hidQ, isDown, pressed, pressTicks, pressBound, heldSince, ticks,
          actSincePress, actSinceHeld, guideVisible, activation, hidAhead, flashed, keyBefore,
          clickBefore, presses, cause, activatedThisHold, holdPolls, polledSinceRelease,
          polledSinceActivation>>

Min(a, b) == IF a < b THEN a ELSE b

\* heldModifiers() == hyperModifiers: the listener first, else the posted flags.
Held == isDown \/ flagsHyper

Init ==
    /\ phys = FALSE /\ flagsHyper = FALSE /\ hidQ = <<>> /\ isDown = FALSE
    /\ pressed = FALSE /\ pressTicks = 0 /\ pressBound = FALSE
    /\ heldSince = FALSE /\ ticks = 0 /\ actSincePress = FALSE /\ actSinceHeld = FALSE
    /\ guideVisible = FALSE
    /\ activation = "none" /\ hidAhead = 0 /\ flashed = FALSE
    /\ keyBefore = FALSE /\ clickBefore = FALSE
    /\ presses = 0 /\ cause = "none"
    /\ activatedThisHold = FALSE /\ holdPolls = 0 /\ polledSinceRelease = FALSE
    /\ polledSinceActivation = FALSE

\* The app's own state, which only main-thread actions change.
app == <<isDown, pressed, pressTicks, pressBound, heldSince, ticks, actSincePress, actSinceHeld,
         guideVisible, hidAhead, flashed, polledSinceActivation>>

---------------------------------------------------------------------------
\* Outside the app.

UserPressesHyper ==
    /\ ~phys /\ presses < MaxPresses
    /\ phys' = TRUE /\ flagsHyper' = TRUE
    /\ hidQ' = Append(hidQ, "down")
    /\ presses' = presses + 1
    /\ activatedThisHold' = FALSE /\ holdPolls' = 0
    /\ UNCHANGED <<app, activation, keyBefore, clickBefore, cause, polledSinceRelease>>

UserReleasesHyper ==
    /\ phys
    /\ phys' = FALSE /\ flagsHyper' = FALSE
    /\ hidQ' = Append(hidQ, "up")
    /\ polledSinceRelease' = FALSE
    /\ UNCHANGED <<app, activation, keyBefore, clickBefore, presses, cause, activatedThisHold, holdPolls>>

\* A real mouse move resets the posted modifier flags (README, Permission).
UserMovesMouse ==
    /\ flagsHyper
    /\ flagsHyper' = FALSE
    /\ UNCHANGED <<app, phys, hidQ, activation, keyBefore, clickBefore, presses, cause,
                   activatedThisHold, holdPolls, polledSinceRelease>>

\* Hyper + letter: the letter's HID value queues behind the hyper key's, its key-down reaches the
\* HID system state at once, and Tinycast brings the bound app forward. Only while the key is down.
UserUsesHotkey ==
    /\ phys /\ activation = "none"
    /\ hidQ' = Append(hidQ, "letter")
    /\ keyBefore' = TRUE
    /\ activation' = "queued" /\ cause' = "hotkey"
    /\ UNCHANGED <<app, phys, flagsHyper, clickBefore, presses, activatedThisHold, holdPolls,
                   polledSinceRelease>>

\* A click on the Dock or on the app's window brings the bound app forward.
UserClicksBoundApp ==
    /\ activation = "none"
    /\ clickBefore' = TRUE
    /\ activation' = "queued" /\ cause' = "click"
    /\ UNCHANGED <<app, phys, flagsHyper, hidQ, keyBefore, presses, activatedThisHold, holdPolls,
                   polledSinceRelease>>

\* A link in another app or a clicked notification brings the bound app forward.
SystemBringsBoundApp ==
    /\ activation = "none"
    /\ activation' = "queued" /\ cause' = "system"
    /\ UNCHANGED <<app, phys, flagsHyper, hidQ, keyBefore, clickBefore, presses, activatedThisHold,
                   holdPolls, polledSinceRelease>>

---------------------------------------------------------------------------
\* On the main thread, one callback at a time.

\* HyperKeyListener.handle for the hyper key: `isDown = down`, and on a key-down `pressedAt` = the
\* HID value's own timestamp. A value that was already waiting when appActivated ran (hidAhead > 0)
\* was pressed before the activation, so activatedAt >= pressedAt.
\* HyperKeyListener.handleKeyDown for the letter: classifyKey against heldModifiers() as it is now,
\* and lastPress keeps the HID value's own timestamp, which is before the activation the hotkey caused.
HidCallback ==
    /\ hidQ /= <<>>
    /\ hidQ' = Tail(hidQ)
    /\ CASE Head(hidQ) = "letter" ->
              /\ pressBound' = Held
              /\ UNCHANGED <<isDown, pressed, pressTicks, actSincePress>>
         [] Head(hidQ) = "down" ->
              /\ isDown' = TRUE /\ pressed' = TRUE /\ pressTicks' = 0
              /\ actSincePress' = (hidAhead > 0)
              /\ UNCHANGED pressBound
         [] Head(hidQ) = "up" ->
              /\ isDown' = FALSE
              /\ UNCHANGED <<pressed, pressTicks, actSincePress, pressBound>>
    /\ hidAhead' = IF hidAhead > 0 THEN hidAhead - 1 ELSE 0
    /\ UNCHANGED <<phys, flagsHyper, heldSince, ticks, actSinceHeld, guideVisible,
                   activation, flashed, keyBefore, clickBefore, presses, cause, activatedThisHold,
                   holdPolls, polledSinceRelease, polledSinceActivation>>

\* Coach.poll: sampleModifiers() (lastHeld, which the decision reads only without Input Monitoring), then
\* HoldTracker.update(hyperHeld:, pressedAt: isDown ? pressedAt : nil, now:), which takes
\* since = pressedAt ?? heldSince ?? now, stores it in heldSince, and shows the guide when
\* activatedAt < since and now - since >= delay.
Poll ==
    LET pt == Min(pressTicks + 1, DelayPolls) IN
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
    /\ polledSinceActivation' = (polledSinceActivation \/ (activation \in {"deciding", "done"} /\ hidQ = <<>>))
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, pressed, pressBound, actSincePress, activation,
                   hidAhead, flashed, keyBefore, clickBefore, presses, cause, activatedThisHold>>

\* Coach.appActivated: tracker.boundAppActivated(now:), then schedule the decision.
\* activatedAt = now is at or after pressedAt and heldSince, whichever are set.
AppActivated ==
    /\ activation = "queued"
    /\ actSincePress' = pressed
    /\ actSinceHeld' = heldSince
    /\ hidAhead' = Len(hidQ)
    /\ activation' = "deciding"
    /\ activatedThisHold' = (activatedThisHold \/ phys)
    /\ polledSinceActivation' = FALSE
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, pressed, pressTicks, pressBound, heldSince, ticks,
                   guideVisible, flashed, keyBefore, clickBefore, presses, cause, holdPolls,
                   polledSinceRelease>>

\* The Task, 150 ms later: missedBinding with lastPress, lastKeyDownAt() and lastClick as they are
\* now. The listener is open, so only the app's own key is a hit; otherwise it flashes only when the
\* user chose the switch: a key went down, or a click landed on the Dock or the app, before it.
DecideMiss ==
    /\ activation = "deciding" /\ hidAhead = 0
    /\ flashed' = (~pressBound /\ (keyBefore \/ clickBefore))
    /\ activation' = "done"
    /\ UNCHANGED <<phys, flagsHyper, hidQ, isDown, pressed, pressTicks, pressBound, heldSince, ticks,
                   actSincePress, actSinceHeld, guideVisible, hidAhead, keyBefore, clickBefore,
                   presses, cause, activatedThisHold, holdPolls, polledSinceRelease,
                   polledSinceActivation>>

Next ==
    \/ UserPressesHyper \/ UserReleasesHyper \/ UserMovesMouse
    \/ UserUsesHotkey \/ UserClicksBoundApp \/ SystemBringsBoundApp
    \/ HidCallback \/ Poll \/ AppActivated \/ DecideMiss

Spec == Init /\ [][Next]_vars

---------------------------------------------------------------------------
\* Properties.

\* A switch made with the hyper hotkey never flashes a miss.
HotkeyNeverFlashes == cause = "hotkey" => ~flashed

\* A switch the system made (a link, a notification) never flashes a miss.
SystemSwitchNeverFlashes == cause = "system" => ~flashed

\* Once the key is up and a poll has seen that, the guide is hidden.
GuideHidesAfterRelease ==
    (~phys /\ hidQ = <<>> /\ polledSinceRelease) => ~guideVisible

\* Holding the key past the delay shows the guide, unless a bound app activated during this hold
\* (shortcut-coach-design.md at 07b4a20, "The hold guide": "no bound app was activated in that time").
GuideShowsOnLongHold ==
    (phys /\ ~activatedThisHold /\ holdPolls > DelayPolls) => guideVisible

\* A bound app activated during this hold keeps the guide hidden until release, from the first
\* poll after the activation once the listener has caught up (same design line).
GuideStaysHiddenAfterActivation ==
    (phys /\ activatedThisHold /\ polledSinceActivation) => ~guideVisible

TypeOK ==
    /\ phys \in BOOLEAN /\ flagsHyper \in BOOLEAN /\ isDown \in BOOLEAN
    /\ hidQ \in Seq({"down", "up", "letter"}) /\ Len(hidQ) <= 2 * MaxPresses + 1
    /\ pressed \in BOOLEAN /\ pressBound \in BOOLEAN /\ actSincePress \in BOOLEAN /\ actSinceHeld \in BOOLEAN
    /\ keyBefore \in BOOLEAN /\ clickBefore \in BOOLEAN
    /\ ticks \in 0..DelayPolls /\ pressTicks \in 0..DelayPolls /\ holdPolls \in 0..(DelayPolls + 1)
    /\ hidAhead \in 0..Len(hidQ)
    /\ activation \in {"none", "queued", "deciding", "done"}
    /\ cause \in {"none", "hotkey", "click", "system"}
=============================================================================
