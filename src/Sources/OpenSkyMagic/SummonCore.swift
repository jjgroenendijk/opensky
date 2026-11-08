// Summoned and reanimated actors as pure rules: how many one caster commands, and which
// one goes when a new one passes the limit. CK wiki "Magic Effect": Summon Creature
// "Summons the specified creature, placing them under the caster's control"; Reanimate
// "If the target is dead, reanimate them". See docs/engine/magic-archetypes.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyMagicInterface

nonisolated public enum SummonCore {
    /// UESP "Skyrim:Conjuration": Twin Souls lets the player have "two atronachs or
    /// reanimated zombies", and adds 1 at entry point 68, so the base is 1.
    public static let baseCommandLimit: Float = 1

    /// `commanded` with `actor` added. Past `limit`, the caster's oldest actors go.
    public static func commanding(
        _ actor: CommandedActor, in commanded: [CommandedActor], limit: Int
    ) -> (kept: [CommandedActor], released: [CommandedActor]) {
        var kept = commanded + [actor]
        var released: [CommandedActor] = []
        while kept.count(where: { $0.caster == actor.caster }) > max(1, limit) {
            guard let oldest = kept.firstIndex(where: { $0.caster == actor.caster }) else { break }
            released.append(kept.remove(at: oldest))
        }
        return (kept: kept, released: released)
    }

    /// The actor that the end of effect `sequence` on `holder` releases.
    public static func ending(
        _ sequence: UInt64, on holder: ReferenceKey, in commanded: [CommandedActor]
    ) -> Int? {
        commanded.firstIndex { $0.holder == holder && $0.sequence == sequence }
    }
}
