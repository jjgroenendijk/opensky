// Weapon-drawn state and attack phase, tracked from the events the behavior
// graph fires back (issue #195, roadmap item 15.4).
//
// The engine raises `attackStart`; the *graph* decides whether an attack state
// was actually entered, how long the windup lasts, and which frame connects.
// So this type is a reader of the graph, not a timer beside it — the same rule
// the footstep director follows, and for the same reason: a phase invented from
// a clock drifts against the animation the player is watching, and a hit
// resolved off that clock lands at a moment the swing is not at.
//
// The two state machines here are deliberately separate. Drawing a weapon and
// swinging it are different sub-behaviors in vanilla (`weapequip.hkx` and
// `1hm_behavior.hkx`) and they interleave: a sheath request during a swing is
// legal and the graph sorts out the order. Folding them into one enum would
// force this type to invent that ordering.
//
// Interruption is the graph's, too. A hit that staggers the player fires
// `staggerStart`, the behavior graph's own transition takes the attack state
// away, and the attack phase drops back to idle here — which is the whole of
// what "attack cancel" needs, because the engine never held a swing timer that
// would have kept running. See docs/engine/melee-combat.md on the two M14
// feature tallies this item was asked to revisit.
//
// Pure value type over a name stream: no clock, no world, no records. That is
// what makes the acceptance test a list of strings.

import Foundation

/// Where the weapon is.
///
/// `drawing` and `sheathing` are the interim states between the engine raising
/// the event and the clip reaching the annotation that actually moves the
/// model. The attachment is on the hand node for `drawn` and `sheathing`, and
/// on the sheathed node for `sheathed` and `drawing`: the weapon stays where it
/// was until `BeginWeaponDraw` or `BeginWeaponSheathe` says the hand has
/// reached it.
nonisolated enum WeaponDrawState: String, Equatable, Sendable, CaseIterable {
    case sheathed
    case drawing
    case drawn
    case sheathing

    /// Whether the attachment rides the hand node in this state.
    var isWeaponInHand: Bool {
        self == .drawn || self == .sheathing
    }

    /// Whether a swing is allowed to start. Vanilla will not attack from a
    /// sheathed weapon; it draws first, which is the engine's job to sequence
    /// and not this type's.
    var canAttack: Bool {
        self == .drawn
    }
}

/// Where a swing is.
///
/// `windup` opens at `attackStart`, `swinging` at `preHitFrame`, `contact` at
/// `HitFrame`, and `recovery` runs until the attack state ends. The hit window
/// is `contact` alone: `preHitFrame` exists to say a hit is imminent, so a
/// consumer that wants to pre-resolve something has a frame to do it in, and
/// the sweep still runs on the contact frame itself.
nonisolated enum MeleeAttackPhase: String, Equatable, Sendable, CaseIterable {
    case idle
    case windup
    case swinging
    case contact
    case recovery

    /// Whether a swing is in progress at all, which is what `IsAttacking`
    /// reports to the graph.
    var isAttacking: Bool {
        self != .idle
    }
}

/// What one observed event did to the state.
nonisolated struct MeleeStateChange: Equatable, Sendable {
    /// The event name that produced it.
    let event: String
    let drawState: WeaponDrawState
    let attackPhase: MeleeAttackPhase
    /// True on the event that moved the weapon between the sheathed node and
    /// the hand node, which is the frame the attachment is rebuilt on.
    let movedAttachment: Bool
    /// True on the contact frame, which is the frame the sweep runs on.
    let openedHitWindow: Bool
}

/// The melee half of the player's graph state, advanced by fired event names.
nonisolated struct MeleeCombatState: Equatable, Sendable {
    private(set) var drawState = WeaponDrawState.sheathed
    private(set) var attackPhase = MeleeAttackPhase.idle
    /// Whether the guard is up, from `blockStart` and `blockStop`.
    private(set) var isBlocking = false
    /// Whether a stagger is playing, from `staggerStart` and `staggerStop`.
    private(set) var isStaggering = false
    /// How many swings have reached their contact frame since construction.
    private(set) var contactCount = 0
    /// Monotonic id of the swing in progress, so a hit filter can say "this
    /// target has already been hit by *this* swing". Zero before the first
    /// swing; rises on every `attackStart`.
    private(set) var swingID = 0

    /// Advances the state by one fired event name, answering with what changed
    /// or nil when the name is not one this machine acts on.
    ///
    /// Names arrive from `LocomotionGraphEventQueue`, which carries every event
    /// the graph fired — combat, magic, footsteps, and the several hundred
    /// vanilla names nothing here consumes. An unrecognized name is dropped
    /// silently: that is the normal case, not a fault.
    ///
    /// Split three ways below because one `switch` over every census name is
    /// past the strict-lint complexity cap, and the three groups are the three
    /// things the graph actually reports: where the weapon is, where the swing
    /// is, and which flags are up.
    @discardableResult
    mutating func handle(_ event: String) -> MeleeStateChange? {
        if let change = handleWeapon(event) {
            return change
        }
        if let change = handleAttack(event) {
            return change
        }
        return handleFlags(event)
    }

    /// Draw and sheath: the two requests and the two clip annotations that
    /// actually move the model.
    private mutating func handleWeapon(_ event: String) -> MeleeStateChange? {
        var moved = false
        switch event {
        case CombatGraphNames.weaponDraw:
            guard drawState == .sheathed || drawState == .sheathing else { return nil }
            drawState = .drawing
        case CombatGraphNames.weaponSheathe:
            guard drawState == .drawn || drawState == .drawing else { return nil }
            drawState = .sheathing
            // A sheath cancels whatever swing was in flight; the graph takes
            // the attack state away at the same moment.
            attackPhase = .idle
        case CombatGraphNames.beginWeaponDraw:
            moved = !drawState.isWeaponInHand
            drawState = .drawn
        case CombatGraphNames.beginWeaponSheathe:
            moved = drawState.isWeaponInHand
            drawState = .sheathed
            attackPhase = .idle
        default:
            return nil
        }
        return change(event, movedAttachment: moved)
    }

    /// The swing's four phases.
    private mutating func handleAttack(_ event: String) -> MeleeStateChange? {
        var openedHitWindow = false
        switch event {
        case CombatGraphNames.attackStart:
            guard drawState.canAttack, !isStaggering else { return nil }
            attackPhase = .windup
            swingID += 1
        case CombatGraphNames.preHitFrame:
            guard attackPhase == .windup else { return nil }
            attackPhase = .swinging
        case CombatGraphNames.hitFrame:
            guard attackPhase == .windup || attackPhase == .swinging else { return nil }
            attackPhase = .contact
            contactCount += 1
            openedHitWindow = true
        case CombatGraphNames.attackStop:
            guard attackPhase != .idle else { return nil }
            attackPhase = .idle
        default:
            return nil
        }
        return change(event, openedHitWindow: openedHitWindow)
    }

    /// Blocking and staggering, both plain edges.
    private mutating func handleFlags(_ event: String) -> MeleeStateChange? {
        switch event {
        case CombatGraphNames.blockStart:
            guard !isBlocking else { return nil }
            isBlocking = true
        case CombatGraphNames.blockStop:
            guard isBlocking else { return nil }
            isBlocking = false
        case CombatGraphNames.staggerStart:
            isStaggering = true
            // The stagger transition is what takes the attack state away, so
            // the phase follows it rather than being cancelled independently.
            attackPhase = .idle
        case CombatGraphNames.staggerStop:
            guard isStaggering else { return nil }
            isStaggering = false
        default:
            return nil
        }
        return change(event)
    }

    /// One change report over the state as it now stands.
    private func change(
        _ event: String,
        movedAttachment: Bool = false,
        openedHitWindow: Bool = false
    ) -> MeleeStateChange {
        MeleeStateChange(
            event: event,
            drawState: drawState,
            attackPhase: attackPhase,
            movedAttachment: movedAttachment,
            openedHitWindow: openedHitWindow
        )
    }

    /// Advances by a whole drained batch, answering with the changes in order.
    @discardableResult
    mutating func handle(_ events: [String]) -> [MeleeStateChange] {
        events.compactMap { handle($0) }
    }

    /// Closes the contact frame, so a swing that fires `HitFrame` and nothing
    /// else does not sit in the hit window forever. Called once per frame after
    /// the batch has been handled.
    mutating func endFrame() {
        if attackPhase == .contact {
            attackPhase = .recovery
        }
    }

    /// Forgets everything, for a teleport or a graph re-attach. The weapon goes
    /// back to sheathed because the newly attached graph starts there.
    mutating func reset() {
        self = MeleeCombatState()
    }
}
