// Allies as pure rules: an actor a spell put under a commander walks after it and
// fights the foes that fight it. CK wiki "Magic Effect": a summon is "under the
// caster's control". The distances are OpenSky values. See docs/engine/combat.md.

import Foundation
import OpenSkyPhysics
import simd

nonisolated public enum CombatAllyRule {
    /// An ally farther than this from its commander walks back.
    public static let followDistance: Float = 300
    /// How close to the commander an ally stops.
    public static let keepDistance: Float = 150
    /// An ally defends its commander against foes this close to the commander.
    public static let defendRadius: Float = 2048

    /// Where `ally` walks to stay near `commander`, or nil when it is near enough.
    public static func followPoint(
        ally: SIMD3<Float>, commander: SIMD3<Float>
    ) -> SIMD3<Float>? {
        let offset = ally - commander
        let distance = simd_length(offset)
        guard distance > followDistance else { return nil }
        return commander + offset / distance * keepDistance
    }

    /// The foe nearest `ally` among those within `defendRadius` of `commander`.
    public static func foe(
        for ally: SIMD3<Float>, defending commander: SIMD3<Float>, among foes: [MeleeTarget]
    ) -> MeleeTarget? {
        nearest(
            foes.filter { simd_distance($0.feet, commander) <= defendRadius }, to: ally
        )
    }

    /// The target nearest `feet`, ties broken by key so a run is reproducible.
    public static func nearest(_ targets: [MeleeTarget], to feet: SIMD3<Float>) -> MeleeTarget? {
        targets.min {
            (simd_distance($0.feet, feet), $0.key) < (simd_distance($1.feet, feet), $1.key)
        }
    }
}
