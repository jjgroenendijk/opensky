// Which hand an NPC with a weapon in each hand strikes with. The order is ours; see
// docs/engine/melee-combat.md#the-left-hand.

public import OpenSkyCombatInterface

/// One NPC's swings: with a one-handed weapon in each hand it strikes right, left,
/// then with both, in turn. Otherwise every swing is the right hand's.
nonisolated public struct NPCStrikes: Equatable, Sendable {
    static let order: [MeleeStrikeHand] = [.right, .left, .dual]

    /// The hand of the swing in progress.
    public private(set) var hand = MeleeStrikeHand.right
    private(set) var count = 0

    /// Starts a swing. An actor that rolls per hand names its hand; any other takes the
    /// next hand of the order.
    mutating func start(dual: Bool, hand rolled: MeleeStrikeHand? = nil) {
        hand = dual ? rolled ?? Self.order[count % Self.order.count] : .right
        count += 1
    }

    /// The right hand's pick was a dual-wield attack, so the swing lands both weapons.
    mutating func swingBoth() {
        hand = .dual
    }

    /// The weapon whose reach the swing has.
    func weapon(right: MeleeWeaponProfile, left: MeleeWeaponProfile?) -> MeleeWeaponProfile {
        hand == .left ? left ?? right : right
    }
}

/// One NPC swing: its hand and the weapons it lands, right first.
nonisolated struct NPCSwing: Equatable, Sendable {
    let hand: MeleeStrikeHand
    let weapons: [MeleeWeaponProfile]
    let shoots: Bool
}
