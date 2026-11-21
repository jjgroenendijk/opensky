// The stats a player's critical hit or sneak attack raises.
// See docs/engine/statistics.md, Critical hits.

public import OpenSkyActorsInterface

nonisolated public enum CriticalHitStats {
    /// One hit sends a critical event when it is critical and a sneak event when it is a
    /// sneak attack. `ownsSneakAttackPerk` is any owned `Mod Sneak Attack Mult` entry.
    public static func stats(
        critical: Bool, sneakAttack: Bool, handType: CombatHandType, ownsSneakAttackPerk: Bool
    ) -> [String] {
        let backstabs = ownsSneakAttackPerk && backstabHands.contains(handType)
        var stats: [String] = []
        for (sent, isSneak) in [(critical, false), (sneakAttack, true)] where sent {
            stats.append("Critical Strikes")
            if isSneak {
                stats.append("Sneak Attacks")
            }
            if backstabs {
                stats.append("Backstabs")
            }
        }
        return stats
    }

    /// `WEAP` animation types 0 to 4 and 8: one-handed weapons, fists, and staves.
    static let backstabHands: Set<CombatHandType> = [
        .handToHand, .sword, .dagger, .axe, .mace, .staff
    ]
}
