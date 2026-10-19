// What one melee blow teaches the characters on both sides, as `SkillUseEvent`s.
// Amounts follow UESP "Skyrim:Leveling" and "Skyrim:Block". The player's swing and an
// NPC's blow on the player both build their uses here. See
// docs/engine/skill-advancement.md.

import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyProgressionInterface

/// One resolved blow, as its skill uses read it.
nonisolated public struct MeleeSkillUseBlow: Equatable, Sendable {
    public var attacker: ReferenceKey
    public var target: ReferenceKey
    public var handType: CombatHandType
    public var kind: MeleeStrikeKind
    public var damage: MeleeDamageResult
    /// Whether the blow reached health that can be damaged.
    public var landed: Bool
    /// Whether the attacker bashed with a shield, which teaches more than a weapon bash.
    public var bashedWithShield: Bool
    /// The swung weapon, for `EPModSkillUsage_AdvanceObjectHasKeyword`.
    public var weapon: ResolvedFormID?

    public init(
        attacker: ReferenceKey,
        target: ReferenceKey,
        handType: CombatHandType,
        kind: MeleeStrikeKind = .normal,
        damage: MeleeDamageResult,
        landed: Bool,
        bashedWithShield: Bool = false,
        weapon: ResolvedFormID? = nil
    ) {
        self.attacker = attacker
        self.target = target
        self.handType = handType
        self.kind = kind
        self.damage = damage
        self.landed = landed
        self.bashedWithShield = bashedWithShield
        self.weapon = weapon
    }
}

nonisolated public enum MeleeSkillUses {
    /// The attacker's weapon skill, or Block for a bash; the blocker's Block for the
    /// absorbed damage; the target's armour skill for the raw strike
    /// (<https://en.uesp.net/wiki/Skyrim:Heavy_Armor>).
    public static func events(
        for blow: MeleeSkillUseBlow, settings: MeleeSkillUseSettings
    ) -> [SkillUseEvent] {
        let damage = blow.damage
        let raw = damage.base * damage.attackMultiplier
        var uses: [SkillUseEvent] = []
        // The weapon skill counts only against health that can be damaged
        // (<https://en.uesp.net/wiki/Skyrim:One-handed>).
        if blow.landed {
            uses.append(attack(blow, settings: settings))
        }
        if damage.wasBlocked {
            uses.append(SkillUseEvent(
                actor: blow.target,
                action: .blockedBlow,
                amount: settings.blocked(
                    absorbed: raw * damage.blockedFraction, withShield: isShield(damage.block)
                )
            ))
        }
        uses.append(SkillUseEvent(actor: blow.target, action: .armorHit, amount: raw))
        return uses
    }

    /// A bash teaches Block, not the weapon's skill. A power bash reports the bash
    /// action, because the action list has no power-bash value.
    private static func attack(
        _ blow: MeleeSkillUseBlow, settings: MeleeSkillUseSettings
    ) -> SkillUseEvent {
        guard blow.kind.isBash else {
            return SkillUseEvent(
                actor: blow.attacker,
                action: .weaponHit(blow.handType),
                amount: blow.damage.base,
                advanceAction: blow.kind.isPowerAttack ? .powerAttack : .normalUsage,
                object: blow.weapon
            )
        }
        return SkillUseEvent(
            actor: blow.attacker,
            action: .bash,
            amount: settings.bash(
                damage: blow.damage.base * blow.damage.attackMultiplier,
                withShield: blow.bashedWithShield
            ),
            advanceAction: .bash
        )
    }

    private static func isShield(_ block: MeleeBlockKind?) -> Bool {
        if case .shield = block {
            return true
        }
        return false
    }
}
