// A swing's shape and reach: reach = fCombatDistance * actorScale * WEAP.reach (UESP WEAP;
// xEdit). Without a WEAP it falls back to bare `fCombatDistance`. The volume is a swept
// capsule from the facing at the contact frame, not the animation pose, so it may hit
// early but never late. See docs/engine/melee-combat.md.

import OpenSkyActorsInterface
public import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
public import OpenSkyPhysics
import simd

nonisolated public enum MeleeSwing: Sendable {
    /// How far a swing reaches, in world units.
    ///
    /// A non-finite or non-positive scale is treated as 1: an actor whose scale
    /// failed to resolve must still be able to swing, and a zero reach would
    /// make every attack silently miss.
    public static func reach(
        weapon: MeleeWeaponProfile,
        settings: CombatSettings,
        actorScale: Float = 1
    ) -> Float {
        let scale = actorScale.isFinite && actorScale > 0 ? actorScale : 1
        let multiplier = weapon.reach.isFinite && weapon.reach > 0 ? weapon.reach : 1
        let base = settings.combatDistance.value
        guard base.isFinite, base > 0 else { return 0 }
        return base * scale * multiplier
    }

    /// The blade's vertical half-extent as a fraction of capsule height, centred on the
    /// chest. Our choice: it hits a target on the same floor, not one on a table.
    public static let bladeHalfExtentFraction: Float = 0.25

    /// The swing's radius, as a fraction of the attacker capsule radius.
    ///
    /// Also an OpenSky decision. The blade itself is thin, but a swing is an
    /// arc and the capsule is its hull, so the radius stands in for the arc's
    /// horizontal width rather than for the steel.
    public static let arcRadiusFraction: Float = 0.75

    /// The swing volume as a sweep query. `facing` is yaw in radians (`cos` on x, `sin` on
    /// y); `reach` comes from `reach(weapon:settings:)`.
    public static func volume(
        feet: SIMD3<Float>,
        capsule: PlayerCapsule,
        facing: Float,
        reach: Float
    ) -> ShapeSweepQuery {
        let chest = feet + SIMD3(0, 0, capsule.height * 0.5)
        let halfExtent = capsule.height * bladeHalfExtentFraction
        return ShapeSweepQuery.capsule(
            (chest + SIMD3(0, 0, halfExtent), chest - SIMD3(0, 0, halfExtent)),
            radius: capsule.radius * arcRadiusFraction,
            direction: SIMD3(cosf(facing), sinf(facing), 0),
            maximumDistance: max(reach, 0)
        )
    }
}
