// The world seam archery resolves a shot through (issue #196, roadmap item
// 15.5), and the values on either side of it.
//
// `MeleeCombatWorld`'s shape, for the same reason: every question below is
// something the session already knows how to answer — where the player is
// aiming from, which actors are resident, what a sweep hits, how to take health
// off a reference, how to play a positional sound, how to put an object in the
// world and take it out again — and naming them together is what lets the
// acceptance tests drive the whole runtime against a fake world with no
// renderer, no window and no game data.
//
// The one thing this seam has that melee's does not is a *spawn* pair.
// Sticking an arrow means putting a new object into the world, and OpenSky
// already has exactly one way to do that: `ReferenceSpawnState`, the component
// a dropped item is drawn from (item 12.1.3). A stuck arrow is that mechanism
// with a different base record and a different transform, which is why the seam
// asks for a key back and hands the key in again to remove it, rather than
// carrying a bespoke drawing channel of its own.
//
// Documented in docs/engine/archery.md.

import simd

/// Who is shooting, and from where.
nonisolated struct ProjectileShooter: Equatable, Sendable {
    /// The shooter's reference, so a shot can never hit its own owner.
    let key: ReferenceKey
    /// The muzzle, world space. The eye rather than the bow hand: the aim ray
    /// is the camera's, and starting the arrow anywhere the camera is not makes
    /// a shot that lands off the reticle by the offset between them.
    let origin: SIMD3<Float>
    /// The camera's forward direction, before the tilt-up angle is applied.
    let aim: SIMD3<Float>
    /// Which perspective is active, which picks the tilt GMST.
    let isFirstPerson: Bool
    /// The cell the shooter is standing in, which is the cell a stuck arrow is
    /// spawned into. Nil outside a streamed world, and then nothing sticks.
    let location: CellSceneLocation?
}

/// One projectile in flight — an arrow or a cast spell (issue #471).
nonisolated struct LiveProjectile: Equatable, Sendable {
    /// Monotonic id, so the trace can name a projectile that no longer exists.
    let id: Int
    let shooter: ReferenceKey
    let profile: ProjectileProfile
    /// What it carries and what it does when it lands. Fixed at launch, for the
    /// reason a bow's damage is: re-deriving it at impact would let a weapon
    /// swap or a re-ready mid-flight change what is already in the air.
    let payload: ProjectilePayload
    let launchPosition: SIMD3<Float>
    let launchDirection: SIMD3<Float>
    /// The cell it was fired in, which is where a stick lands.
    let location: CellSceneLocation?
    var state: ProjectileFlightState

    /// Where the shot is now, which is what a readout draws.
    var position: SIMD3<Float> {
        state.position
    }
}

/// Why a projectile stopped existing.
nonisolated enum ProjectileOutcome: String, Equatable, Sendable, CaseIterable {
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

    /// Whether the projectile ended by touching something.
    var isImpact: Bool {
        self == .hitActor || self == .hitStatic
    }
}

/// One finished shot, kept for the panel's last-trajectory readout. Carries
/// everything the issue asks that readout to show: spawn point, impact point
/// and flight time.
nonisolated struct ProjectileTrace: Equatable, Sendable {
    let id: Int
    let launchPosition: SIMD3<Float>
    let launchDirection: SIMD3<Float>
    /// Where it ended. For a miss this is simply where it was given up on.
    let endPosition: SIMD3<Float>
    /// Seconds of flight.
    let flightTime: Float
    /// Path length travelled, world units.
    let travelled: Float
    /// How far below the aim line it ended, world units. Zero for a shot with
    /// no gravity.
    let drop: Float
    let outcome: ProjectileOutcome
    /// What it hit, when it hit an actor.
    let target: ReferenceKey?
    /// Health actually taken off; zero for a miss or an unarmoured non-actor.
    /// A spell takes health off through the effect runtime instead, so this
    /// stays zero for one and `spellHit` carries what it did.
    let appliedDamage: Float
    /// The SNDR the impact chain resolved, or nil where it named none.
    let sound: FormID?
    /// Whether the arrow was left in the world at the impact point.
    let stuck: Bool
    /// What a landed spell applied, or nil for an arrow and for a spell that
    /// reached nobody (issue #471).
    let spellHit: SpellHitReport?
    /// Whether this hit should make its target hostile: every arrow, and a
    /// spell whose effects are hostile. Read by the combat loop, so a healing
    /// spell cast at a follower does not start a fight.
    let provokes: Bool
}

/// One arrow left standing in whatever it hit.
nonisolated struct StuckProjectile: Equatable, Sendable {
    /// The projectile that made it, so the trace and the registry agree.
    let projectileID: Int
    /// The AMMO to draw it from. A stuck arrow is the ammunition's own ground
    /// model, which is the model a spent arrow is picked back up as.
    let base: FormID
    let location: CellSceneLocation
    let position: SIMD3<Float>
    /// Rotation in the same radians `PlacedReference.Placement` uses, aligned
    /// with the flight direction at impact so the shaft points into the surface.
    let rotation: SIMD3<Float>
    /// The reference it stuck in, for the readout. Nil for terrain and for
    /// anything the sweep could not name.
    let host: FormID?
}

/// Applying one landed spell, wherever it came from.
///
/// Its own protocol for the reason `ScriptHitReporting` is: a projectile, a
/// target-actor cast and a concentration beam all land the same way, and the
/// session implements the answer once for all three (issue #471).
@MainActor
protocol SpellHitApplying: AnyObject {
    /// Applies one landed spell to the actors it reached.
    ///
    /// - Returns: what was applied. `SpellHitReport.none` when the session has
    ///   no effect runtime, which a synthetic scene is, so a spell that could
    ///   not be applied is reported rather than counted as landed.
    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport
}

/// Everything the archery runtimes need from the session around them.
///
/// `WeaponEnchantmentApplying` is refined for the reason `SpellHitApplying` is: an
/// enchanted bow and an enchanted blade apply through one implementation (issue
/// #472).
@MainActor
protocol ProjectileWorld: ScriptHitReporting, SpellHitApplying, WeaponEnchantmentApplying {
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

    /// The MATT type of what was struck, or nil where it names none. Feeds the
    /// IPCT lookup exactly as the ground material feeds a footstep's.
    func projectileMaterial(at position: SIMD3<Float>) -> FormID?

    /// Takes `amount` off `target`'s health.
    ///
    /// - Returns: true when the damage was actually applied, so a hit on a
    ///   reference with no actor-value state is reported rather than silently
    ///   counted as a hit that did nothing.
    @discardableResult
    func applyProjectileDamage(_ amount: Float, to target: ReferenceKey) -> Bool

    /// Plays one resolved impact at the contact point.
    func playProjectileImpact(_ impact: ResolvedMeleeImpact, at position: SIMD3<Float>)

    /// Removes one arrow of `ammunition` from the player through the M12
    /// inventory runtime.
    ///
    /// - Returns: true when one was actually removed. A false answer stops the
    ///   shot: an empty quiver must not fire.
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
