// The left hand's and both hands' strikes: which button a press came from, when two
// presses make one dual strike, and which weapons the strike lands with.
// See docs/engine/melee-combat.md#the-left-hand.

import OpenSkyActorsInterface
import OpenSkyCombatInterface

extension MeleeCombatRuntime {
    /// The left button is a level, so its press is the frame it goes down.
    func noteLeftButton(_ held: Bool) {
        if held, !wasLeftHeld {
            pendingLeftAttack = true
        }
        wasLeftHeld = held
    }

    /// Latches this frame's presses into the hold clock. A press is dropped rather
    /// than queued when the weapon is away: a press in a latch would fire a swing the
    /// moment the draw finished. Mid-swing it may chain. A drawn bow's button is archery's.
    func latchPresses(blocking: Bool) {
        let right = pendingAttack && !weapon.handType.isRanged
        let left = pendingLeftAttack && leftWeapon != nil
        pendingAttack = false
        pendingLeftAttack = false
        guard state.drawState.canAttack, queuedOutcome == nil else { return }
        if right {
            press(.right, asBash: blocking)
        }
        if left {
            press(.left, asBash: false)
        }
    }

    /// The second hand's press joins a press still being timed into a dual strike.
    private func press(_ hand: MeleeStrikeHand, asBash: Bool) {
        guard hold.pending != nil else {
            hold.pressed(asBash: asBash)
            pendingHand = hand
            return
        }
        if
            pendingHand != hand, pendingHand != .dual, hold.pending == .normal,
            canStrikeDual, hold.heldSeconds <= MeleeHold.dualPressWindow
        {
            pendingHand = .dual
        }
    }

    /// Both hands hold a one-handed melee weapon.
    var canStrikeDual: Bool {
        leftWeapon != nil && weapon.handType.isOneHandedMelee
    }

    /// A dual press powers up only while both buttons stay down.
    func isHeld(_ intent: MeleeIntent) -> Bool {
        switch pendingHand {
        case .right: intent.attackHeld
        case .left: intent.leftAttackHeld
        case .dual: intent.attackHeld && intent.leftAttackHeld
        }
    }

    /// The event that starts `kind` with the pending hand. Only the right hand bashes.
    func startEvent(_ kind: MeleeStrikeKind, direction: MeleePowerDirection) -> String {
        switch (strikeHand, kind) {
        case (.left, .power): direction.leftHandEventName
        case (.left, _): CombatGraphNames.attackStartLeftHand
        case (.dual, .power): CombatGraphNames.attackPowerStartDualWield
        case (.dual, _): CombatGraphNames.attackStartDualWield
        case (.right, .normal): CombatGraphNames.attackStart
        case (.right, .power): direction.eventName
        case (.right, .bash): CombatGraphNames.bashStart
        case (.right, .powerBash): CombatGraphNames.bashPowerStart
        }
    }

    /// The weapon whose reach the strike in progress has.
    var strikeWeapon: MeleeWeaponProfile {
        strikeHand == .left ? leftWeapon ?? weapon : weapon
    }

    /// Every weapon the strike in progress lands: both for a dual strike.
    var strikeWeapons: [MeleeWeaponProfile] {
        strikeWeapons(for: strikeHand)
    }

    func strikeWeapons(for hand: MeleeStrikeHand) -> [MeleeWeaponProfile] {
        hand.weapons(right: weapon, left: leftWeapon)
    }

    func resetHands() {
        strikeHand = .right
        pendingHand = .right
        pendingLeftAttack = false
        wasLeftHeld = false
    }
}

nonisolated extension CombatHandType {
    var isRanged: Bool {
        self == .bow || self == .crossbow
    }

    /// A sword, dagger, war axe, or mace: what dual wielding takes.
    var isOneHandedMelee: Bool {
        switch self {
        case .sword, .dagger, .axe, .mace: true
        default: false
        }
    }
}

nonisolated extension MeleeStrikeHand {
    /// Every weapon a strike with this hand lands, right first. Without a left weapon
    /// every strike is the right hand's.
    func weapons(right: MeleeWeaponProfile, left: MeleeWeaponProfile?) -> [MeleeWeaponProfile] {
        switch (self, left) {
        case let (.left, left?): [left]
        case let (.dual, left?): [right, left]
        default: [right]
        }
    }
}
