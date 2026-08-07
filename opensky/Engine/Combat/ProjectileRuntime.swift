// Live projectiles (issue #196, roadmap item 15.5, scope points 3 to 5): what
// is in the air right now, how it advances, what it hits, and what is left
// behind.
//
// The clock is the whole design. Frames arrive at whatever rate the display
// gives; a trajectory that integrated the frame time directly would land in a
// different place on a 60 Hz display than on a 120 Hz one, and the issue asks
// for deterministic trajectories. So this type accumulates frame time and
// advances every projectile on `WalkController.fixedTimeStep`, exactly as
// `DynamicBodyWorld` does — and for exactly the same reason. A shot fired from
// a given pose lands in the same place on every machine.
//
// Ordering is by projectile id throughout, which is allocation order. Two runs
// of the same session therefore resolve impacts in the same sequence.
//
// Everything it touches the world with goes through `ProjectileWorld`, so the
// whole runtime is testable against a fake with no renderer and no game data.
//
// Documented in docs/engine/archery.md.

import Foundation
import simd

@MainActor
final class ProjectileRuntime {
    /// How many finished shots the trace keeps. A handful, because the panel
    /// shows the newest and a reader is looking at the last thing they did.
    static let traceLimit = 16
    /// How many arrows may be left standing in the world at once.
    ///
    /// UESP "Skyrim:Archery" states vanilla's own cap — "Only 15 missed arrows
    /// or bolts can be present at once, once a 16th has been fired the first
    /// one fired will despawn" — and that is the number and the eviction rule
    /// used here. It applies to every stuck arrow rather than to missed ones
    /// alone, because this engine does not model arrow retrieval from a corpse
    /// (M18+) and so has no second category to count separately.
    static let stuckLimit = 15
    /// Ceiling on fixed steps run for one frame, so a long stall costs bounded
    /// time. The same bound `WalkController.maximumFrameTime` puts on the
    /// capsule.
    static let maximumFrameTime = WalkController.maximumFrameTime

    let settings: ArcherySettings
    /// Projectiles in the air, in id order.
    private(set) var live: [LiveProjectile] = []
    /// The most recent finished shots, oldest first.
    private(set) var trace: [ProjectileTrace] = []
    /// Arrows standing in the world, oldest first, with the key each was
    /// spawned under.
    private(set) var stuck: [(arrow: StuckProjectile, key: ReferenceKey?)] = []
    private(set) var firedCount = 0
    private(set) var impactCount = 0

    /// Resolves the IPCT chain for a landed arrow. Nil in a synthetic session,
    /// and then impacts are silent rather than absent.
    var impacts: MeleeImpactResolver?

    private weak var world: (any ProjectileWorld)?
    private var nextID = 1
    private var accumulatedTime: Float = 0

    init(settings: ArcherySettings, world: (any ProjectileWorld)? = nil) {
        self.settings = settings
        self.world = world
    }

    /// Attaches (or detaches) the world this runtime resolves against.
    func attach(world: (any ProjectileWorld)?) {
        self.world = world
        reset()
    }

    // MARK: - Firing

    /// Launches one projectile and consumes the arrow it came from.
    ///
    /// The inventory removal happens first and gates everything after it: an
    /// empty quiver must not put an arrow in the air, and a shot that failed to
    /// find one must not be counted.
    ///
    /// - Returns: the projectile, or nil when the shot could not be taken.
    @discardableResult
    func fire(_ shot: ArcheryShot) -> LiveProjectile? {
        guard let world, shot.profile.isFlyable else { return nil }
        if let ammunition = shot.ammunition, !world.consumeArrow(ammunition) {
            return nil
        }
        let shooter = world.projectileShooter
        let direction = ProjectileFlight.aimDirection(
            cameraForward: shooter.aim,
            tiltDegrees: settings.tiltUpAngle(firstPerson: shooter.isFirstPerson).value
        )
        let projectile = LiveProjectile(
            id: nextID,
            shooter: shooter.key,
            profile: shot.profile,
            damage: shot.damage,
            weapon: shot.weapon,
            ammunition: shot.ammunition,
            launchPosition: shooter.origin,
            launchDirection: direction,
            location: shooter.location,
            state: ProjectileFlight.launch(
                from: shooter.origin,
                along: direction,
                profile: shot.profile,
                speedScale: shot.damage.drawFraction
            )
        )
        nextID += 1
        firedCount += 1
        live.append(projectile)
        return projectile
    }

    // MARK: - Simulation

    /// Advances every live projectile by `frameTime`, in fixed steps.
    ///
    /// - Returns: the traces of every projectile that ended this frame.
    @discardableResult
    func advance(by frameTime: Float) -> [ProjectileTrace] {
        evictUnloadedStuckArrows()
        guard !live.isEmpty else {
            accumulatedTime = 0
            return []
        }
        accumulatedTime += min(max(frameTime.isFinite ? frameTime : 0, 0), Self.maximumFrameTime)
        var finished: [ProjectileTrace] = []
        while accumulatedTime + Float.ulpOfOne >= WalkController.fixedTimeStep, !live.isEmpty {
            finished += stepAll(dt: WalkController.fixedTimeStep)
            accumulatedTime -= WalkController.fixedTimeStep
        }
        return finished
    }

    /// Removes every live projectile without resolving it, and forgets the
    /// accumulated time. Called when the bridge resets, so a teleport does not
    /// carry an arrow through a door and land it in the wrong cell — and on a
    /// world-state reload, which is what makes an in-flight projectile a thing
    /// that does not survive a save/load.
    func despawnAll() {
        for projectile in live {
            record(projectile, outcome: .cancelled, at: projectile.position, impact: nil)
        }
        live = []
        accumulatedTime = 0
    }

    /// Everything: live projectiles, stuck arrows, trace, counts.
    func reset() {
        despawnAll()
        clearStuckArrows()
        clearTrace()
    }

    /// Empties the trace and both counts without disturbing anything in the
    /// world, which is what the panel's own clear control means.
    func clearTrace() {
        trace = []
        firedCount = 0
        impactCount = 0
    }

    /// Pulls every stuck arrow back out of the world. The panel's clean-up
    /// control, and what a full reset runs.
    func clearStuckArrows() {
        removeStuckArrows(Array(stuck.indices))
    }

    // MARK: - Private

    /// One fixed step over every live projectile.
    private func stepAll(dt: Float) -> [ProjectileTrace] {
        var survivors: [LiveProjectile] = []
        survivors.reserveCapacity(live.count)
        var finished: [ProjectileTrace] = []
        for var projectile in live {
            let previous = projectile.state.position
            projectile.state = ProjectileFlight.step(
                projectile.state, profile: projectile.profile, dt: dt
            )
            if let impact = impact(of: projectile, from: previous) {
                finished.append(resolve(projectile, impact: impact))
                continue
            }
            if let outcome = expiry(of: projectile) {
                finished.append(
                    record(projectile, outcome: outcome, at: projectile.position, impact: nil)
                )
                continue
            }
            survivors.append(projectile)
        }
        live = survivors
        return finished
    }

    /// What this step's travelled segment touched, or nil.
    private func impact(
        of projectile: LiveProjectile,
        from previous: SIMD3<Float>
    ) -> ProjectileImpact? {
        guard let world else { return nil }
        return ProjectileImpactQuery.first(
            step: ProjectileStep(
                from: previous,
                to: projectile.state.position,
                radius: projectile.profile.collisionRadius
            ),
            targets: world.projectileTargets(),
            shooter: projectile.shooter,
            sweep: { world.sweepProjectile($0) }
        )
    }

    /// Whether the projectile has run out of range or lifetime.
    ///
    /// Range is the shorter of the PROJ's own `range` and the GMST
    /// `fVisibleNavmeshMoveDist`, because UESP is explicit that past the latter
    /// a shot "will phase through targets without doing any damage" — so
    /// continuing to fly it would be simulating something that can no longer
    /// hit anything. A record or a setting of zero bounds nothing rather than
    /// stopping the shot immediately.
    private func expiry(of projectile: LiveProjectile) -> ProjectileOutcome? {
        let limits = [projectile.profile.range, settings.visibleMoveDistance.value]
            .filter { $0 > 0 }
        if let range = limits.min(), projectile.state.travelled >= range {
            return .outOfRange
        }
        let lifetime = projectile.profile.lifetime
        if lifetime > 0, projectile.state.age >= lifetime {
            return .expired
        }
        return nil
    }

    /// Damage, impact sound and stick for one landed arrow.
    private func resolve(
        _ projectile: LiveProjectile,
        impact: ProjectileImpact
    ) -> ProjectileTrace {
        impactCount += 1
        var applied: Float = 0
        if
            let target = impact.target, let world,
            world.applyProjectileDamage(projectile.damage.applied, to: target)
        {
            applied = projectile.damage.applied
        }
        let sound = playImpact(at: impact.position)
        let didStick = stick(projectile, at: impact)
        return record(
            projectile,
            outcome: impact.isActor ? .hitActor : .hitStatic,
            at: impact.position,
            impact: impact,
            appliedDamage: applied,
            sound: sound,
            stuck: didStick
        )
    }

    /// The IPCT chain for a hit, played where the world can play it.
    private func playImpact(at position: SIMD3<Float>) -> FormID? {
        guard let world, let impacts else { return nil }
        // An arrow resolves its impact through the *ammunition's* chain rather
        // than a bow's: item 15.4 built the resolver around a
        // `MeleeWeaponProfile`, and an arrow has no INAM of its own, so the
        // unarmed profile's nil data set is what an arrow honestly carries
        // until AMMO grows an impact link. The lookup is left in place so that
        // adding one is a one-line change rather than a new chain.
        guard
            let resolved = impacts.resolve(
                weapon: .unarmed, material: world.projectileMaterial(at: position)
            )
        else { return nil }
        world.playProjectileImpact(resolved, at: position)
        return resolved.sound
    }

    /// Leaves the arrow standing in what it hit, evicting the oldest when the
    /// cap is reached.
    private func stick(_ projectile: LiveProjectile, at impact: ProjectileImpact) -> Bool {
        guard
            let world,
            let base = projectile.ammunition,
            let location = projectile.location
        else { return false }
        let arrow = StuckProjectile(
            projectileID: projectile.id,
            base: base,
            location: location,
            position: impact.position,
            rotation: ProjectileImpactQuery.stuckRotation(
                alongFlight: projectile.state.velocity
            ),
            host: impact.reference
        )
        guard let key = world.spawnStuckProjectile(arrow) else { return false }
        stuck.append((arrow, key))
        if stuck.count > Self.stuckLimit {
            removeStuckArrows(Array(stuck.indices.prefix(stuck.count - Self.stuckLimit)))
        }
        return true
    }

    /// Drops stuck arrows whose cell is no longer resident, so an unloading
    /// cell takes them with it.
    private func evictUnloadedStuckArrows() {
        guard let world, !stuck.isEmpty else { return }
        let resident = world.residentProjectileCells()
        guard !resident.isEmpty else { return }
        removeStuckArrows(
            stuck.indices.filter { !resident.contains(stuck[$0].arrow.location) }
        )
    }

    /// Removes the stuck arrows at `indices` from the world and from the
    /// registry.
    private func removeStuckArrows(_ indices: [Int]) {
        guard !indices.isEmpty else { return }
        let doomed = Set(indices)
        for index in indices.sorted() {
            guard let key = stuck[index].key else { continue }
            world?.removeStuckProjectile(key)
        }
        stuck = stuck.indices.filter { !doomed.contains($0) }.map { stuck[$0] }
    }

    /// Files one finished projectile in the trace.
    @discardableResult
    private func record(
        _ projectile: LiveProjectile,
        outcome: ProjectileOutcome,
        at position: SIMD3<Float>,
        impact: ProjectileImpact?,
        appliedDamage: Float = 0,
        sound: FormID? = nil,
        stuck: Bool = false
    ) -> ProjectileTrace {
        let aimed = projectile.launchPosition
            + projectile.launchDirection * projectile.state.travelled
        let entry = ProjectileTrace(
            id: projectile.id,
            launchPosition: projectile.launchPosition,
            launchDirection: projectile.launchDirection,
            endPosition: position,
            flightTime: projectile.state.age,
            travelled: projectile.state.travelled,
            drop: max(0, aimed.z - position.z),
            outcome: outcome,
            target: impact?.target,
            appliedDamage: appliedDamage,
            sound: sound,
            stuck: stuck
        )
        trace.append(entry)
        if trace.count > Self.traceLimit {
            trace.removeFirst(trace.count - Self.traceLimit)
        }
        return entry
    }
}

/// One shot, assembled by `ArcheryRuntime` and handed to the projectile
/// runtime. A value rather than five arguments, because every one of them is
/// resolved at the same moment — the frame the graph fired `arrowRelease` — and
/// splitting them would let a caller mix a bow's damage with another shot's
/// profile.
nonisolated struct ArcheryShot: Equatable, Sendable {
    let profile: ProjectileProfile
    let damage: ArcheryDamageResult
    /// The WEAP that fired it; nil for a shot with no bow behind it.
    let weapon: FormID?
    /// The AMMO consumed. Nil means "consume nothing", which is what the dev
    /// spawn control fires with so that a developer inspecting a trajectory
    /// does not have to keep a quiver stocked.
    let ammunition: FormID?
}
