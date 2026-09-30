// Where a bow shot is, tracked from the events the behavior graph fires. The
// graph decides the draw timing and the release frame; this type only reads it.
// Whether the bow is out is `MeleeCombatState.drawState`. A pure value type
// over a name stream. See docs/engine/archery.md.

import Foundation

/// Where a shot is. `nocked` opens at `arrowAttach`, `drawing` at `BowDraw`,
/// `drawn` at `bowDrawn`, and `loosed` at `arrowRelease`, the frame a projectile
/// spawns. `loosed` lasts one batch: `endFrame()` returns it to `idle`.
nonisolated public enum ArcheryShotPhase: String, Equatable, Sendable, CaseIterable {
    case idle
    case nocked
    case drawing
    case drawn
    case loosed

    /// Whether a shot is in progress at all, which is what a readout means by
    /// "aiming".
    public var isDrawing: Bool {
        self == .nocked || self == .drawing || self == .drawn
    }

    /// Whether the bow has reached full draw, which is what `bBowDrawn`
    /// reports to the graph and what the damage curve reads.
    public var isFullyDrawn: Bool {
        self == .drawn
    }
}

/// What one observed event did to the shot.
nonisolated public struct ArcheryStateChange: Equatable, Sendable {
    public let phase: ArcheryShotPhase
    /// True on the frame an arrow became a visible attachment in the draw hand.
    public let attachedArrow: Bool
    /// True on the frame the arrow left the string, which is the frame a
    /// projectile spawns on.
    public let loosedArrow: Bool
}

/// The archery half of the player's graph state, advanced by fired event names.
nonisolated public struct ArcheryState: Equatable, Sendable {
    public private(set) var phase = ArcheryShotPhase.idle
    /// Whether an arrow is currently attached to the draw hand, from
    /// `arrowAttach` and `arrowDetach`.
    public private(set) var hasArrowAttached = false
    /// How many arrows have left the string since construction.
    public private(set) var shotCount = 0
    /// Monotonic id of the shot in progress, so a spawned projectile can say
    /// which draw produced it. Zero before the first nock.
    public private(set) var shotID = 0

    /// Advances the state by one fired event name, answering with what changed or
    /// nil. An unknown name is dropped: that is the normal case. Split in two to stay
    /// under the complexity cap: the draw half and the arrow half.
    @discardableResult
    public mutating func handle(_ event: String) -> ArcheryStateChange? {
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
        return change()
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
        return change(attachedArrow: attached, loosedArrow: loosed)
    }

    /// One change report over the state as it now stands.
    private func change(
        attachedArrow: Bool = false,
        loosedArrow: Bool = false
    ) -> ArcheryStateChange {
        ArcheryStateChange(
            phase: phase,
            attachedArrow: attachedArrow,
            loosedArrow: loosedArrow
        )
    }

    /// Advances by a whole drained batch, answering with the changes in order.
    @discardableResult
    public mutating func handle(_ events: [String]) -> [ArcheryStateChange] {
        events.compactMap { handle($0) }
    }

    /// Closes the release frame, so a shot that fires `arrowRelease` and
    /// nothing else does not sit in the spawn window forever. Called once per
    /// frame after the batch has been handled.
    public mutating func endFrame() {
        if phase == .loosed {
            phase = .idle
        }
    }

    /// Forgets everything, for a teleport or a graph re-attach.
    public mutating func reset() {
        self = ArcheryState()
    }
}
