// Where a bow shot is, tracked from the events the behavior graph fires back
// (issue #196, roadmap item 15.5).
//
// `MeleeCombatState`'s rule, applied to a shot: the engine raises
// `bowDrawStart` and `attackRelease`, and the *graph* decides whether a draw
// was entered, how long it takes to reach full, and which frame the arrow
// leaves the string. This type reads that answer; it does not time a draw
// beside it.
//
// One state machine rather than melee's two, because there is nothing here
// corresponding to draw-and-sheath: whether the bow is in hand at all is
// already `MeleeCombatState.drawState`, and this machine describes only the
// shot on top of it. `ArcheryRuntime` refuses to start a draw unless that
// machine says the weapon is out, so the two compose without either knowing
// the other's internals.
//
// Pure value type over a name stream: no clock, no world, no projectiles. That
// is what makes the acceptance test a list of strings.
//
// Documented in docs/engine/archery.md.

import Foundation

/// Where a shot is.
///
/// `nocked` opens at `arrowAttach`, `drawing` at `BowDraw`, `drawn` at
/// `bowDrawn`, and `loosed` at `arrowRelease` — which is the one frame a
/// projectile spawns on. `loosed` lasts a single batch: `endFrame()` returns it
/// to `idle`, exactly as the melee contact frame closes, so a graph that fires
/// `arrowRelease` and nothing else cannot sit in the spawn window.
nonisolated enum ArcheryShotPhase: String, Equatable, Sendable, CaseIterable {
    case idle
    case nocked
    case drawing
    case drawn
    case loosed

    /// Whether a shot is in progress at all, which is what a readout means by
    /// "aiming".
    var isDrawing: Bool {
        self == .nocked || self == .drawing || self == .drawn
    }

    /// Whether the bow has reached full draw, which is what `bBowDrawn`
    /// reports to the graph and what the damage curve reads.
    var isFullyDrawn: Bool {
        self == .drawn
    }
}

/// What one observed event did to the shot.
nonisolated struct ArcheryStateChange: Equatable, Sendable {
    let event: String
    let phase: ArcheryShotPhase
    /// True on the frame an arrow became a visible attachment in the draw hand.
    let attachedArrow: Bool
    /// True on the frame the arrow left the string, which is the frame a
    /// projectile spawns on.
    let loosedArrow: Bool
}

/// The archery half of the player's graph state, advanced by fired event names.
nonisolated struct ArcheryState: Equatable, Sendable {
    private(set) var phase = ArcheryShotPhase.idle
    /// Whether an arrow is currently attached to the draw hand, from
    /// `arrowAttach` and `arrowDetach`.
    private(set) var hasArrowAttached = false
    /// How many arrows have left the string since construction.
    private(set) var shotCount = 0
    /// Monotonic id of the shot in progress, so a spawned projectile can say
    /// which draw produced it. Zero before the first nock.
    private(set) var shotID = 0

    /// Advances the state by one fired event name, answering with what changed
    /// or nil when the name is not one this machine acts on.
    ///
    /// Names arrive from `LocomotionGraphEventQueue`, which carries every event
    /// the graph fired. An unrecognized name is dropped silently: that is the
    /// normal case, not a fault.
    /// Split in two because one `switch` over every name it acts on is past the
    /// strict-lint complexity cap, and the two halves are the two things the
    /// graph reports: where the draw has got to, and where the arrow is.
    @discardableResult
    mutating func handle(_ event: String) -> ArcheryStateChange? {
        if let change = handleDraw(event) {
            return change
        }
        return handleArrow(event)
    }

    /// The draw's own progress: pulling, reaching full, collapsing, ending.
    private mutating func handleDraw(_ event: String) -> ArcheryStateChange? {
        switch event {
        case ArcheryGraphNames.bowDraw:
            guard phase == .nocked || phase == .idle else { return nil }
            if phase == .idle {
                shotID += 1
            }
            phase = .drawing
        case ArcheryGraphNames.bowDrawn:
            guard phase.isDrawing else { return nil }
            phase = .drawn
        case ArcheryGraphNames.bowReset:
            phase = .idle
            hasArrowAttached = false
        case ArcheryGraphNames.bowRelease:
            guard phase == .loosed || phase.isDrawing else { return nil }
            phase = .idle
        default:
            return nil
        }
        return change(event)
    }

    /// Where the arrow itself is: in the hand, gone from the hand, or gone from
    /// the bow.
    private mutating func handleArrow(_ event: String) -> ArcheryStateChange? {
        var attached = false
        var loosed = false
        switch event {
        case ArcheryGraphNames.arrowAttach:
            attached = !hasArrowAttached
            hasArrowAttached = true
            if phase == .idle {
                phase = .nocked
                shotID += 1
            }
        case ArcheryGraphNames.arrowRelease:
            // Accepted from any drawing phase and from `idle` too: a graph that
            // fires the release without having reported a nock has still
            // loosed an arrow, and refusing it would drop a real shot in order
            // to protect a state machine's tidiness.
            phase = .loosed
            shotCount += 1
            loosed = true
            if shotID == 0 {
                shotID = 1
            }
        case ArcheryGraphNames.arrowDetach:
            hasArrowAttached = false
        default:
            return nil
        }
        return change(event, attachedArrow: attached, loosedArrow: loosed)
    }

    /// One change report over the state as it now stands.
    private func change(
        _ event: String,
        attachedArrow: Bool = false,
        loosedArrow: Bool = false
    ) -> ArcheryStateChange {
        ArcheryStateChange(
            event: event,
            phase: phase,
            attachedArrow: attachedArrow,
            loosedArrow: loosedArrow
        )
    }

    /// Advances by a whole drained batch, answering with the changes in order.
    @discardableResult
    mutating func handle(_ events: [String]) -> [ArcheryStateChange] {
        events.compactMap { handle($0) }
    }

    /// Closes the release frame, so a shot that fires `arrowRelease` and
    /// nothing else does not sit in the spawn window forever. Called once per
    /// frame after the batch has been handled.
    mutating func endFrame() {
        if phase == .loosed {
            phase = .idle
        }
    }

    /// Forgets everything, for a teleport or a graph re-attach.
    mutating func reset() {
        self = ArcheryState()
    }
}
