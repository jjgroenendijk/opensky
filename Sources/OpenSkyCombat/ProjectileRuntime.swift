// Live projectiles: what is in the air, how it advances, what it hits, and what
// stays behind. Frame time accumulates into `PhysicsStep.fixedTimeStep` steps,
// so a trajectory is the same at 60 Hz and 120 Hz. Impacts resolve in
// projectile-id order. World access goes through `ProjectileWorld`.
// See docs/engine/projectiles.md.

import Foundation
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import simd

@MainActor
public final class ProjectileRuntime {
    /// How many finished shots the trace keeps. A handful, because the panel
    /// shows the newest and a reader is looking at the last thing they did.
    public static let traceLimit = 16
    /// How many arrows may stay stuck in the world at once. UESP "Skyrim:Archery":
    /// "Only 15 missed arrows or bolts can be present at once"; the oldest despawns.
    /// It applies to every stuck arrow, because arrow retrieval is not modeled.
    public static let stuckLimit = 15
    /// Ceiling on fixed steps run for one frame, so a long stall costs bounded
    /// time. The same bound `PhysicsStep.maximumFrameTime` puts on the
    /// capsule.
    public static let maximumFrameTime = PhysicsStep.maximumFrameTime

    public let settings: ArcherySettings
    /// How an EFIT area becomes a radius in world units. Settable, because the
    /// conversion is uncertain; see `MagicAreaSettings`.
    public var areaSettings = MagicAreaSettings.documentedDefaults
    /// Projectiles in the air, in id order.
    public private(set) var live: [LiveProjectile] = []
    /// The most recent finished shots, oldest first.
    public private(set) var trace: [ProjectileTrace] = []
    /// Arrows standing in the world, oldest first, with the key each was
    /// spawned under.
    public private(set) var stuck: [(arrow: StuckProjectile, key: ReferenceKey?)] = []
    public private(set) var firedCount = 0
    public private(set) var impactCount = 0

    /// Resolves the IPCT chain for a landed arrow. Nil in a synthetic session,
    /// and then impacts are silent rather than absent.
    public var impacts: MeleeImpactResolver?

    /// `private(set)` rather than `private` so the satellite files can read it
    /// while only `attach(world:)` in this file can write it.
    public private(set) weak var world: (any ProjectileWorld)?
    private var nextID = 1
    private var accumulatedTime: Float = 0

    public init(settings: ArcherySettings, world: (any ProjectileWorld)? = nil) {
        self.settings = settings
        self.world = world
    }

    /// Attaches (or detaches) the world this runtime resolves against.
    public func attach(world: (any ProjectileWorld)?) {
        self.world = world
        reset()
    }

    // MARK: - Firing

    /// Launches one projectile and consumes what it was fired from. The inventory
    /// removal comes first: an empty quiver fires nothing. A spell already paid in
    /// `CasterRuntime`.
    /// - Returns: the projectile, or nil when the shot could not be taken.
    @discardableResult
    public func fire(_ shot: ProjectileShot) -> LiveProjectile? {
        guard let world else { return nil }
        return fire(shot, from: world.projectileShooter)
    }

    /// Launches one projectile from a shooter other than the camera holder, such as
    /// an NPC's spell. The flight, impact query, and bounds are the same.
    @discardableResult
    public func fire(_ shot: ProjectileShot, from shooter: ProjectileShooter) -> LiveProjectile? {
        guard let world, shot.profile.isFlyable else { return nil }
        if let ammunition = shot.consumedAmmunition, !world.consumeArrow(ammunition) {
            return nil
        }
        // The archery tilt-up angle compensates for a bow's arrow drop, so it
        // applies to a bow's shot and to nothing else; a spell leaves straight
        // down the aim ray.
        let tilt = shot.usesArcheryTilt
            ? settings.tiltUpAngle(firstPerson: shooter.isFirstPerson).value
            : 0
        let direction = ProjectileFlight.aimDirection(
            cameraForward: shooter.aim, tiltDegrees: tilt
        )
        let projectile = LiveProjectile(
            id: nextID,
            shooter: shooter.key,
            profile: shot.profile,
            payload: shot.payload,
            launchPosition: shooter.origin,
            launchDirection: direction,
            location: shooter.location,
            state: ProjectileFlight.launch(
                from: shooter.origin,
                along: direction,
                profile: shot.profile,
                speedScale: shot.speedScale
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
    public func advance(by frameTime: Float) -> [ProjectileTrace] {
        evictUnloadedStuckArrows()
        guard !live.isEmpty else {
            accumulatedTime = 0
            return []
        }
        accumulatedTime += min(max(frameTime.isFinite ? frameTime : 0, 0), Self.maximumFrameTime)
        var finished: [ProjectileTrace] = []
        while accumulatedTime + Float.ulpOfOne >= PhysicsStep.fixedTimeStep, !live.isEmpty {
            finished += stepAll(dt: PhysicsStep.fixedTimeStep)
            accumulatedTime -= PhysicsStep.fixedTimeStep
        }
        return finished
    }

    /// Removes every live projectile without resolving it, and forgets the
    /// accumulated time. Called when the bridge resets, so a teleport does not
    /// carry an arrow through a door and land it in the wrong cell — and on a
    /// world-state reload, which is what makes an in-flight projectile a thing
    /// that does not survive a save/load.
    public func despawnAll() {
        for projectile in live {
            record(projectile, outcome: .cancelled, at: projectile.position, impact: nil)
        }
        live = []
        accumulatedTime = 0
    }

    /// Everything: live projectiles, stuck arrows, trace, counts.
    public func reset() {
        despawnAll()
        clearStuckArrows()
        clearTrace()
    }

    /// Empties the trace and both counts without disturbing anything in the
    /// world, which is what the panel's own clear control means.
    public func clearTrace() {
        trace = []
        firedCount = 0
        impactCount = 0
    }

    /// Pulls every stuck arrow back out of the world. The panel's clean-up
    /// control, and what a full reset runs.
    public func clearStuckArrows() {
        removeStuckArrows(Array(stuck.indices))
    }

    /// Drops the first `count` live projectiles without recording anything.
    /// Internal for `ProjectileRuntimeBounds.swift`, which records them itself
    /// before calling this; `live` stays `private(set)` so nothing else can.
    public func removeOldestLive(_ count: Int) {
        live.removeFirst(min(max(0, count), live.count))
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

    /// Whether the projectile has run out of range or lifetime. Range is the shorter
    /// of the PROJ `range` and GMST `fVisibleNavmeshMoveDist`; past the latter a shot
    /// does no damage (UESP). A zero value bounds nothing.
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

    /// Damage or effects, impact sound and stick for one landed projectile.
    private func resolve(
        _ projectile: LiveProjectile,
        impact: ProjectileImpact
    ) -> ProjectileTrace {
        impactCount += 1
        let applied = applyArrow(projectile, impact: impact)
        let spellHit = applySpell(projectile, impact: impact)
        let sound = playImpact(at: impact.position)
        let didStick = stick(projectile, at: impact)
        return record(
            projectile,
            outcome: impact.isActor ? .hitActor : .hitStatic,
            at: impact.position,
            impact: impact,
            appliedDamage: applied,
            sound: sound,
            stuck: didStick,
            spellHit: spellHit
        )
    }

    /// Leaves the arrow standing in what it hit, evicting the oldest when the
    /// cap is reached.
    ///
    /// Only an arrow sticks. A spell projectile is spent on impact and leaves
    /// nothing behind — the hit art and the explosion that would are M26.
    private func stick(_ projectile: LiveProjectile, at impact: ProjectileImpact) -> Bool {
        guard
            let world,
            let base = projectile.payload.arrow?.ammunition,
            let location = projectile.location
        else { return false }
        let arrow = StuckProjectile(
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

    /// Removes the stuck arrows at `indices` from the world and from the registry.
    /// Internal, so `ProjectileRuntimeBounds.swift` can reach it.
    public func removeStuckArrows(_ indices: [Int]) {
        guard !indices.isEmpty else { return }
        let doomed = Set(indices)
        for index in indices.sorted() {
            guard let key = stuck[index].key else { continue }
            world?.removeStuckProjectile(key)
        }
        stuck = stuck.indices.filter { !doomed.contains($0) }.map { stuck[$0] }
    }

    /// Files one finished projectile in the trace.
    /// Internal for the same reason `removeStuckArrows(_:)` is.
    @discardableResult
    public func record(
        _ projectile: LiveProjectile,
        outcome: ProjectileOutcome,
        at position: SIMD3<Float>,
        impact: ProjectileImpact?,
        appliedDamage: Float = 0,
        sound: FormID? = nil,
        stuck: Bool = false,
        spellHit: SpellHitReport? = nil
    ) -> ProjectileTrace {
        let aimed = projectile.launchPosition
            + projectile.launchDirection * projectile.state.travelled
        let entry = ProjectileTrace(
            id: projectile.id,
            launchPosition: projectile.launchPosition,
            endPosition: position,
            flightTime: projectile.state.age,
            travelled: projectile.state.travelled,
            drop: max(0, aimed.z - position.z),
            outcome: outcome,
            target: impact?.target,
            appliedDamage: appliedDamage,
            sound: sound,
            stuck: stuck,
            spellHit: spellHit,
            // Only a landed hit provokes: a projectile that expired in the air
            // never reached anybody to make angry.
            provokes: outcome.isImpact && projectile.payload.provokes
        )
        trace.append(entry)
        if trace.count > Self.traceLimit {
            trace.removeFirst(trace.count - Self.traceLimit)
        }
        return entry
    }
}
