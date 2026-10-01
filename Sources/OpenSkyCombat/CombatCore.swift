// The combat decisions as pure functions: what the player holds, which arrow
// a shot takes, which spells an actor may cast. `CombatCoordinator` is the
// shell that reads the world. See docs/engine/coordinators.md.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyProgressionInterface

/// One item the player wears, as the hand rules see it.
nonisolated public enum CombatWornItem: Equatable, Sendable {
    case weapon(MeleeWeaponProfile)
    case shield
    case other
}

/// Which of the player's hands hold a readied spell.
nonisolated public struct ReadiedHands: Equatable, Sendable {
    public var right: Bool
    public var left: Bool

    public static let none = ReadiedHands(right: false, left: false)

    public init(right: Bool, left: Bool) {
        self.right = right
        self.left = left
    }
}

/// Both hands as the behavior graph counts them.
nonisolated public struct CombatHands: Equatable, Sendable {
    public let weapon: MeleeWeaponProfile
    public let offHand: CombatHandType

    public init(weapon: MeleeWeaponProfile, offHand: CombatHandType) {
        self.weapon = weapon
        self.offHand = offHand
    }
}

/// One known spell with the facts the combat gates read.
nonisolated public struct CombatSpellCandidate: Equatable, Sendable {
    public let option: CombatSpellOption
    /// False for an ability or a power.
    public let isSpell: Bool
    public let targetsSelf: Bool
    /// The cast loop carries out its delivery.
    public let isDeliverable: Bool
    /// At least one effect entry is flagged hostile.
    public let isHostile: Bool
    /// Its ETYP lets the cast hand ready it.
    public let fitsHand: Bool

    public init(
        option: CombatSpellOption,
        isSpell: Bool,
        targetsSelf: Bool,
        isDeliverable: Bool,
        isHostile: Bool,
        fitsHand: Bool
    ) {
        self.option = option
        self.isSpell = isSpell
        self.targetsSelf = targetsSelf
        self.isDeliverable = isDeliverable
        self.isHostile = isHostile
        self.fitsHand = fitsHand
    }
}

/// The combat rules over plain values. It reads no world state.
nonisolated public enum CombatCore {
    /// `Mod Attack Damage` (35): Armsman, Barbarian and Overdraw
    /// (docs/formats/perks.md).
    public static let attackDamageEntryPoint = PerkEntryPoint(rawValue: 35)
    /// `Mod Percent Blocked` (39): Shield Wall.
    public static let percentBlockedEntryPoint = PerkEntryPoint(rawValue: 39)

    /// A readied spell wins, because readying it unequipped that hand. A
    /// two-handed weapon fills both hands, a second weapon is the off-hand one,
    /// and a shield is slot 39. Torches are not indexed, so a lit hand is empty.
    public static func hands(worn: [CombatWornItem], readied: ReadiedHands) -> CombatHands {
        let held = wornHands(worn)
        return CombatHands(
            weapon: readied.right ? .readiedSpell : held.weapon,
            offHand: readied.left ? .spell : held.offHand
        )
    }

    private static func wornHands(_ worn: [CombatWornItem]) -> CombatHands {
        let weapons = worn.compactMap { item -> MeleeWeaponProfile? in
            guard case let .weapon(profile) = item else { return nil }
            return profile
        }
        let emptyOffHand: CombatHandType = worn.contains(.shield) ? .shield : .handToHand
        guard let right = weapons.first else {
            return CombatHands(weapon: .unarmed, offHand: emptyOffHand)
        }
        if right.handType.occupiesBothHands {
            return CombatHands(weapon: right, offHand: right.handType)
        }
        if weapons.count > 1 {
            return CombatHands(weapon: right, offHand: weapons[1].handType)
        }
        return CombatHands(weapon: right, offHand: emptyOffHand)
    }

    /// The first worn bow. Crossbows are out of scope (docs/engine/archery.md).
    public static func bow(worn: [CombatWornItem]) -> MeleeWeaponProfile {
        for case let .weapon(profile) in worn where profile.handType == .bow {
            return profile
        }
        return .unarmed
    }

    /// A hand holding a readied spell gives its button to the cast loop.
    public static func meleeIntent(_ intent: MeleeIntent, readied: ReadiedHands) -> MeleeIntent {
        var masked = intent
        if readied.right {
            masked.attack = false
        }
        if readied.left {
            masked.block = false
        }
        return masked
    }

    /// The first carried arrow that flies. Ammunition has its own equip slot
    /// that OpenSky does not model, so the stable stack order picks it.
    public static func arrow(
        carried: [FormID],
        resolve: (FormID) -> ArcheryAmmunition?
    ) -> ArcheryAmmunition? {
        for item in carried {
            if let arrow = resolve(item) {
                return arrow
            }
        }
        return nil
    }

    /// Health as a fraction in 0...1. Full when the maximum is not positive.
    public static func healthFraction(current: Float, maximum: Float) -> Float {
        guard maximum > 0 else { return 1 }
        return min(1, max(0, current / maximum))
    }

    /// Nil unless the spell is a hostile, deliverable, hand-cast spell aimed
    /// at someone else (docs/engine/ai-spell-use.md).
    public static func spellOption(_ candidate: CombatSpellCandidate) -> CombatSpellOption? {
        guard
            candidate.isSpell,
            !candidate.targetsSelf,
            candidate.isDeliverable,
            candidate.isHostile,
            candidate.fitsHand
        else { return nil }
        return candidate.option
    }

    public static func castingProfile(_ facts: CombatCastingFacts) -> CombatCastingProfile {
        CombatCastingProfile(
            magicka: facts.magicka,
            options: facts.spells.compactMap(spellOption).sorted { $0.spell < $1.spell }
        )
    }

    /// The player answers from its melee guard, every other actor from its
    /// combat behavior machine.
    public static func block(
        of target: ReferenceKey,
        playerIsBlocking: Bool,
        machineBlock: MeleeBlockKind?
    ) -> MeleeBlockKind? {
        guard target == .player else { return machineBlock }
        return playerIsBlocking ? .weapon : nil
    }
}
