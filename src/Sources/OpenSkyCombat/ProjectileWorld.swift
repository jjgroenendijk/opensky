// The world seam archery resolves a shot through, and the values on either
// side. Shaped like `MeleeCombatWorld`, plus a spawn pair: a stuck arrow is a
// `ReferenceSpawnState` spawn, so the seam returns a key and takes it back to
// remove the arrow. See docs/engine/projectiles.md.

public import OpenSkyBehavior
public import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagicInterface
public import OpenSkyPhysics
public import OpenSkyProgressionInterface
import simd

/// Why a projectile stopped existing.
nonisolated public enum ProjectileOutcome: String, Equatable, Sendable, CaseIterable {
    /// Struck an actor capsule.
    case hitActor
    /// Struck placed static geometry.
    case hitStatic
    /// Travelled past the shorter of its PROJ `range` and
    /// `fVisibleNavmeshMoveDist` without touching anything.
    case outOfRange
    /// Ran out its PROJ `lifetime`.
    case expired
    /// Removed by a reset — a teleport, a world-state reload, the readout's clear.
    case cancelled
    /// Set off in the air by its PROJ explosion timer or proximity.
    case detonated

    /// Whether the projectile ended by touching something.
    public var isImpact: Bool {
        self == .hitActor || self == .hitStatic
    }
}

/// One finished shot, kept for the readout's last-trajectory readout: spawn
/// point, impact point, and flight time.
nonisolated public struct ProjectileTrace: Equatable, Sendable {
    /// Where it ended. For a miss this is simply where it was given up on.
    public let endPosition: SIMD3<Float>
    /// Seconds of flight.
    public let flightTime: Float
    /// Path length travelled, world units.
    public let travelled: Float
    /// How far below the aim line it ended, world units. Zero for a shot with
    /// no gravity.
    public let drop: Float
    public let outcome: ProjectileOutcome
    /// What it hit, when it hit an actor.
    public let target: ReferenceKey?
    /// Health actually taken off; zero for a miss or an unarmoured non-actor.
    /// A spell takes health off through the effect runtime instead, so this
    /// stays zero for one and `spellHit` carries what it did.
    public let appliedDamage: Float
    /// The MATT type of the surface struck, which the impact chain resolved against.
    public var material: FormID?
    /// Whether the arrow was left in the world at the impact point.
    public let stuck: Bool
    /// What a landed spell applied, or nil for an arrow and for a spell that reached
    /// nobody.
    public let spellHit: SpellHitReport?
    /// Whether this hit should make its target hostile: every arrow, and a
    /// spell whose effects are hostile. Read by the combat loop, so a healing
    /// spell cast at a follower does not start a fight.
    public let provokes: Bool
}

/// One arrow left standing in whatever it hit.
nonisolated public struct StuckProjectile: Equatable, Sendable {
    /// The AMMO to draw it from. A stuck arrow is the ammunition's own ground
    /// model, which is the model a spent arrow is picked back up as.
    public let base: FormID
    public let location: CellSceneLocation
    public let position: SIMD3<Float>
    /// Rotation in the same radians `PlacedReference.Placement` uses, aligned
    /// with the flight direction at impact so the shaft points into the surface.
    public let rotation: SIMD3<Float>
    /// The reference it stuck in, for the readout. Nil for terrain and for
    /// anything the sweep could not name.
    public let host: FormID?
}

/// Everything the archery runtimes need from the session around them. It refines
/// `WeaponEnchantmentApplying`, so bows and blades share one implementation.
@MainActor
public protocol ProjectileWorld: ScriptHitReporting, SkillUseReporting, SpellHitApplying,
    WeaponEnchantmentApplying, ImpactMaterialReading
{
    /// Where the player is aiming from, this frame.
    var projectileShooter: ProjectileShooter { get }

    /// Every actor a shot could hit. Actors only — the caller's filter, not the
    /// runtime's, exactly as `MeleeCombatWorld.meleeTargets()` is. The same
    /// `MeleeTarget` value, because a capsule is a capsule and a second type
    /// naming the same three fields would only be able to disagree with it.
    func projectileTargets() -> [MeleeTarget]

    /// First static-collision touch along `query`, or nil where it is clear.
    /// Normally `ShapeSweeper.firstHit` over the streamer's broadphase.
    func sweepProjectile(_ query: ShapeSweepQuery) -> ShapeSweepHit?

    /// Takes `amount` off `target`'s health. `shooter` is who fired it: the player,
    /// or a trap whose script called `Weapon.Fire`.
    ///
    /// - Returns: true when the damage was actually applied, so a hit on a
    ///   reference with no actor-value state is reported rather than silently
    ///   counted as a hit that did nothing.
    @discardableResult
    func applyProjectileDamage(
        _ amount: Float, to target: ReferenceKey, from shooter: ReferenceKey
    ) -> Bool

    /// A projectile left its shooter; the session shows its muzzle flash.
    func projectileLaunched(_ projectile: LiveProjectile)
    /// Plays one resolved impact at the contact point.
    func playProjectileImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>)
    /// The default blood of a hit on an actor whose impact data resolved nothing.
    func showDefaultBlood(on target: ReferenceKey, at position: SIMD3<Float>, melee: Bool)

    /// Removes one arrow of `ammunition` from the player's inventory.
    /// - Returns: true when one was removed. False stops the shot: an empty quiver must
    ///   not fire.
    @discardableResult
    func consumeArrow(_ ammunition: FormID) -> Bool

    /// Puts a stuck arrow into the world.
    ///
    /// - Returns: the generated reference key it was spawned under, or nil when
    ///   the session cannot spawn — a synthetic scene, or a shot with no cell.
    @discardableResult
    func spawnStuckProjectile(_ arrow: StuckProjectile) -> ReferenceKey?

    /// Takes a stuck arrow back out, for the count cap and for a cell that has
    /// unloaded.
    func removeStuckProjectile(_ key: ReferenceKey)

    /// Which cells are resident right now, so stuck arrows can leave with the
    /// cell that holds them. An empty set means "nothing is streamed", which
    /// leaves every stuck arrow alone rather than evicting all of them.
    func residentProjectileCells() -> Set<CellSceneLocation>

    /// Raises one census-named event on the player's graph.
    ///
    /// - Returns: true when the graph declared the name, which is how an event
    ///   that could not be delivered becomes visible instead of assumed.
    @discardableResult
    func raiseArcheryEvent(_ name: String) -> Bool

    /// Writes one census-named variable on the player's graph.
    func writeArcheryVariable(_ value: BehaviorVariableValue, named name: String)

    @discardableResult
    func giveRecoveredArrow(_ ammunition: FormID, to target: ReferenceKey) -> Bool
    func showArcheryNotice(_ text: String)
    func arrowRecoveryMultiplier(of shooter: ReferenceKey) -> Float
    /// Whether a shot from `shooter` would land on `target` unseen, read before the damage.
    func projectileIsSneakAttack(by shooter: ReferenceKey, on target: ReferenceKey) -> Bool
}

extension ProjectileWorld {
    public func projectileLaunched(_: LiveProjectile) {}

    public func showDefaultBlood(on _: ReferenceKey, at _: SIMD3<Float>, melee _: Bool) {}

    /// Puts one arrow into `target`'s inventory. False where nothing holds items.
    @discardableResult
    public func giveRecoveredArrow(_: FormID, to _: ReferenceKey) -> Bool {
        false
    }

    /// Shows a HUD notice, such as the empty-quiver message.
    public func showArcheryNotice(_: String) {}

    /// The shooter's `Mod Recover Arrow Chance` perks, as a factor on the chance.
    public func arrowRecoveryMultiplier(of _: ReferenceKey) -> Float {
        1
    }

    public func projectileIsSneakAttack(by _: ReferenceKey, on _: ReferenceKey) -> Bool {
        false
    }
}
