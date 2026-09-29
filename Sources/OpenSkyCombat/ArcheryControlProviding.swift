// Main-app archery inspection seam (issue #196, roadmap item 15.5, scope point
// 6): the shot state, the live projectile count, the last-trajectory readout,
// and the dev spawn control the issue asks for.
//
// One snapshot value rather than a bag of protocol properties, for the same
// reason `MeleeCombatSnapshot` is one: the readout has to be a pure function of
// a single engine observation, not of several taken microseconds apart while an
// arrow is in the air between them.
//
// AppKit-free, so it compiles into `openskycli` alongside the app.

import Foundation

/// One finished shot as a panel spells it.
nonisolated public struct ProjectileTraceReadout: Equatable, Sendable {
    public let id: Int
    /// Spawn point, impact point and flight time — the three the issue names.
    public let launch: SIMD3<Float>
    public let end: SIMD3<Float>
    public let flightTime: Float
    /// Path length travelled, world units.
    public let travelled: Float
    /// How far below the aim line the shot ended, world units.
    public let drop: Float
    public let outcome: ProjectileOutcome
    /// The actor struck, as its `ReferenceKey` description; nil for a miss or
    /// a hit on static geometry.
    public let target: String?
    public let appliedDamage: Float
    /// The SNDR that played, or nil when the chain named none.
    public let sound: String?
    /// Whether the arrow was left standing in what it hit.
    public let stuck: Bool

    public init(
        id: Int,
        launch: SIMD3<Float>,
        end: SIMD3<Float>,
        flightTime: Float,
        travelled: Float,
        drop: Float,
        outcome: ProjectileOutcome,
        target: String?,
        appliedDamage: Float,
        sound: String?,
        stuck: Bool
    ) {
        self.id = id
        self.launch = launch
        self.end = end
        self.flightTime = flightTime
        self.travelled = travelled
        self.drop = drop
        self.outcome = outcome
        self.target = target
        self.appliedDamage = appliedDamage
        self.sound = sound
        self.stuck = stuck
    }
}

/// One observation of the archery runtime.
nonisolated public struct ArcherySnapshot: Equatable, Sendable {
    /// False when no archery runtime is attached — no game data, or a demo
    /// scene. Every other field is then empty and the panel says so rather
    /// than showing a convincing zero.
    public let isAvailable: Bool
    public let phase: ArcheryShotPhase
    /// Whether an arrow is currently in the draw hand.
    public let hasArrowAttached: Bool
    /// How long the attack button has been held on the current draw, seconds,
    /// and the hold that produced the last shot.
    public let heldSeconds: Float
    public let lastHeldSeconds: Float
    /// The draw-time damage fraction the current hold has earned, `0...1`.
    public let drawFraction: Float
    /// The equipped bow's editor name, or "none".
    public let bowName: String
    public let bowDamage: Float
    public let bowSpeed: Float
    /// The selected arrow's editor name, or "none"; its AMMO damage; and the
    /// PROJ flight numbers it carries.
    public let arrowName: String
    public let arrowDamage: Float
    public let projectileName: String
    public let projectileSpeed: Float
    public let projectileGravityFactor: Float
    public let projectileRange: Float
    /// Draws asked for, arrows loosed, impacts resolved.
    public let drawRequestCount: Int
    public let firedCount: Int
    public let impactCount: Int
    /// How many arrows are in the air and how many are standing in the world.
    public let liveCount: Int
    public let stuckCount: Int
    /// The finished-shot trace, oldest first.
    public let trace: [ProjectileTraceReadout]
    /// Every archery GMST with its resolved value and where it came from.
    public let settings: [String]

    /// The reading with no runtime attached.
    public static let unavailable = ArcherySnapshot(
        isAvailable: false,
        phase: .idle,
        hasArrowAttached: false,
        heldSeconds: 0,
        lastHeldSeconds: 0,
        drawFraction: 0,
        bowName: "—",
        bowDamage: 0,
        bowSpeed: 0,
        arrowName: "—",
        arrowDamage: 0,
        projectileName: "—",
        projectileSpeed: 0,
        projectileGravityFactor: 0,
        projectileRange: 0,
        drawRequestCount: 0,
        firedCount: 0,
        impactCount: 0,
        liveCount: 0,
        stuckCount: 0,
        trace: [],
        settings: []
    )

    public init(
        isAvailable: Bool,
        phase: ArcheryShotPhase,
        hasArrowAttached: Bool,
        heldSeconds: Float,
        lastHeldSeconds: Float,
        drawFraction: Float,
        bowName: String,
        bowDamage: Float,
        bowSpeed: Float,
        arrowName: String,
        arrowDamage: Float,
        projectileName: String,
        projectileSpeed: Float,
        projectileGravityFactor: Float,
        projectileRange: Float,
        drawRequestCount: Int,
        firedCount: Int,
        impactCount: Int,
        liveCount: Int,
        stuckCount: Int,
        trace: [ProjectileTraceReadout],
        settings: [String]
    ) {
        self.isAvailable = isAvailable
        self.phase = phase
        self.hasArrowAttached = hasArrowAttached
        self.heldSeconds = heldSeconds
        self.lastHeldSeconds = lastHeldSeconds
        self.drawFraction = drawFraction
        self.bowName = bowName
        self.bowDamage = bowDamage
        self.bowSpeed = bowSpeed
        self.arrowName = arrowName
        self.arrowDamage = arrowDamage
        self.projectileName = projectileName
        self.projectileSpeed = projectileSpeed
        self.projectileGravityFactor = projectileGravityFactor
        self.projectileRange = projectileRange
        self.drawRequestCount = drawRequestCount
        self.firedCount = firedCount
        self.impactCount = impactCount
        self.liveCount = liveCount
        self.stuckCount = stuckCount
        self.trace = trace
        self.settings = settings
    }
}

@MainActor
public protocol ArcheryControlProviding: AnyObject {
    var archerySnapshot: ArcherySnapshot { get }

    /// Fires one projectile from the current aim without touching the quiver.
    ///
    /// The dev spawn control scope point 6 asks for. It reaches the same
    /// `ArcheryRuntime.loose` the graph's `arrowRelease` reaches, so a shot
    /// taken from the sidebar is indistinguishable downstream from one the
    /// player took — which is what makes the control a way to verify the
    /// binding rather than a second implementation of it. The quiver is left
    /// alone on purpose: a developer watching a trajectory should not have to
    /// keep buying arrows.
    ///
    /// - Returns: a human-readable outcome, which the panel shows verbatim.
    @discardableResult
    func spawnDevProjectile() -> String

    /// Removes everything in the air right now, resolving nothing.
    func despawnProjectiles()

    /// Pulls every stuck arrow back out of the world.
    func clearStuckProjectiles()

    /// Empties the trace and the counts, without disturbing anything in the
    /// world.
    func clearProjectileTrace()
}
