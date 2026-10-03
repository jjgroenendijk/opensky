// The world seam archery resolves a shot through, and the values on either
// side. Shaped like `MeleeCombatWorld`, plus a spawn pair: a stuck arrow is a
// `ReferenceSpawnState` spawn, so the seam returns a key and takes it back to
// remove the arrow. See docs/engine/projectiles.md.

import OpenSkyBehavior
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import simd

/// Who is shooting, and from where.
nonisolated public struct ProjectileShooter: Equatable, Sendable {
    /// The shooter's reference, so a shot can never hit its own owner.
    public let key: ReferenceKey
    /// The muzzle, world space. The eye rather than the bow hand: the aim ray
    /// is the camera's, and starting the arrow anywhere the camera is not makes
    /// a shot that lands off the reticle by the offset between them.
    public let origin: SIMD3<Float>
    /// The camera's forward direction, before the tilt-up angle is applied.
    public let aim: SIMD3<Float>
    /// Which perspective is active, which picks the tilt GMST.
    public let isFirstPerson: Bool
    /// The cell the shooter is standing in, which is the cell a stuck arrow is
    /// spawned into. Nil outside a streamed world, and then nothing sticks.
    public let location: CellSceneLocation?

    public init(
        key: ReferenceKey,
        origin: SIMD3<Float>,
        aim: SIMD3<Float>,
        isFirstPerson: Bool,
        location: CellSceneLocation?
    ) {
        self.key = key
        self.origin = origin
        self.aim = aim
        self.isFirstPerson = isFirstPerson
        self.location = location
    }
}

/// One projectile in flight: an arrow or a cast spell.
nonisolated public struct LiveProjectile: Equatable, Sendable {
    /// Monotonic id, so the trace can name a projectile that no longer exists.
    public let id: Int
    public let shooter: ReferenceKey
    public let profile: ProjectileProfile
    /// What it carries and what it does when it lands. Fixed at launch, for the
    /// reason a bow's damage is: re-deriving it at impact would let a weapon
    /// swap or a re-ready mid-flight change what is already in the air.
    public let payload: ProjectilePayload
    public let launchPosition: SIMD3<Float>
    public let launchDirection: SIMD3<Float>
    /// The cell it was fired in, which is where a stick lands.
    public let location: CellSceneLocation?
    public var state: ProjectileFlightState

    /// Where the shot is now, which is what a readout draws.
    public var position: SIMD3<Float> {
        state.position
    }
}

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
    /// Removed by a reset — a teleport, a world-state reload, the panel's clear.
    case cancelled
    /// Set off in the air by its PROJ explosion timer or proximity.
    case detonated

    /// Whether the projectile ended by touching something.
    public var isImpact: Bool {
        self == .hitActor || self == .hitStatic
    }
}

/// One finished shot, kept for the panel's last-trajectory readout: spawn
/// point, impact point, and flight time.
nonisolated public struct ProjectileTrace: Equatable, Sendable {
    public let id: Int
    public let launchPosition: SIMD3<Float>
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
    /// The SNDR the impact chain resolved, or nil where it named none.
    public let sound: FormID?
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
    WeaponEnchantmentApplying
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

    /// The MATT type an impact plays against, or nil where it names none. The
    /// session reports the ground, as for a melee hit.
    func projectileMaterial() -> FormID?

    /// Takes `amount` off `target`'s health.
    ///
    /// - Returns: true when the damage was actually applied, so a hit on a
    ///   reference with no actor-value state is reported rather than silently
    ///   counted as a hit that did nothing.
    @discardableResult
    func applyProjectileDamage(_ amount: Float, to target: ReferenceKey) -> Bool

    /// Plays one resolved impact at the contact point.
    func playProjectileImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>)

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
}
