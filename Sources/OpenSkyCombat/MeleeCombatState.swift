// Draw state and attack phase, tracked from the events the behavior graph fires.
// The graph decides windup length and the contact frame; this type only reads
// it. Draw and swing are two machines, because vanilla interleaves them. A
// stagger ends the attack through the graph. A pure value type over a name
// stream. See docs/engine/melee-combat.md.

import Foundation
import OpenSkyActorsInterface

/// Where a swing is. `windup` opens at `attackStart`, `swinging` at
/// `preHitFrame`, `contact` at `HitFrame`, and `recovery` runs until the attack
/// state ends. The hit window is `contact` alone.
nonisolated public enum MeleeAttackPhase: String, Equatable, Sendable, CaseIterable {
    case idle
    case windup
    case swinging
    case contact
    case recovery

    /// Whether a swing is in progress at all, which is what `IsAttacking`
    /// reports to the graph.
    public var isAttacking: Bool {
        self != .idle
    }
}

/// What one observed event did to the state.
nonisolated public struct MeleeStateChange: Equatable, Sendable {
    public let drawState: WeaponDrawState
    public let attackPhase: MeleeAttackPhase
    /// True on the event that moved the weapon between the sheathed node and
    /// the hand node, which is the frame the attachment is rebuilt on.
    public let movedAttachment: Bool
    /// True on the contact frame, which is the frame the sweep runs on.
    public let openedHitWindow: Bool
}

/// The melee half of the player's graph state, advanced by fired event names.
nonisolated public struct MeleeCombatState: Equatable, Sendable {
    public private(set) var drawState = WeaponDrawState.sheathed
    public private(set) var attackPhase = MeleeAttackPhase.idle
    /// Whether the guard is up, from `blockStart` and `blockStop`.
    public private(set) var isBlocking = false
    /// Whether a stagger is playing, from `staggerStart` and `staggerStop`.
    public private(set) var isStaggering = false
    /// How many swings have reached their contact frame since construction.
    public private(set) var contactCount = 0
    /// Monotonic id of the swing in progress, so a hit filter can say "this
    /// target has already been hit by *this* swing". Zero before the first
    /// swing; rises on every `attackStart`.
    public private(set) var swingID = 0

    /// Advances the state by one fired event name, answering with what changed or
    /// nil. An unknown name is dropped: that is the normal case. Split three ways to
    /// stay under the complexity cap: weapon, swing, and flags.
    @discardableResult
    public mutating func handle(_ event: String) -> MeleeStateChange? {
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
        // Two names per edge, because only some equip clips carry `BeginWeaponDraw`
        // (`1HM_Equip.hkx` does, `Dag_Equip.hkx` does not). `WeapEquip_Out` fires for
        // all of them at the clip end, so it is the backstop; the annotation wins.
        case CombatGraphNames.beginWeaponDraw, CombatGraphNames.weapEquipOut:
            moved = !drawState.isWeaponInHand
            drawState = .drawn
        case CombatGraphNames.beginWeaponSheathe, CombatGraphNames.unequipOut:
            moved = drawState.isWeaponInHand
            drawState = .sheathed
            attackPhase = .idle
        default:
            return nil
        }
        return change(movedAttachment: moved)
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
        return change(openedHitWindow: openedHitWindow)
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
        return change()
    }

    /// One change report over the state as it now stands.
    private func change(
        movedAttachment: Bool = false,
        openedHitWindow: Bool = false
    ) -> MeleeStateChange {
        MeleeStateChange(
            drawState: drawState,
            attackPhase: attackPhase,
            movedAttachment: movedAttachment,
            openedHitWindow: openedHitWindow
        )
    }

    /// Advances by a whole drained batch, answering with the changes in order.
    @discardableResult
    public mutating func handle(_ events: [String]) -> [MeleeStateChange] {
        events.compactMap { handle($0) }
    }

    /// Closes the contact frame, so a swing that fires `HitFrame` and nothing
    /// else does not sit in the hit window forever. Called once per frame after
    /// the batch has been handled.
    public mutating func endFrame() {
        if attackPhase == .contact {
            attackPhase = .recovery
        }
    }

    /// Forgets everything, for a teleport or a graph re-attach. The weapon goes
    /// back to sheathed because the newly attached graph starts there.
    public mutating func reset() {
        self = MeleeCombatState()
    }
}
