// Each frame: splashes where actors and loose bodies enter water, damage where a fast
// heavy body strikes an actor, and knockdowns in fast water. Keeps the last pushes for
// the readout. The rules are in `ImpulseRules` and `WaterImpacts` (docs/engine/impulses.md).

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyPhysics
import simd

/// The loose bodies a push can reach, and the solver that moves them.
@MainActor
public protocol ImpulseBodyWorld: AnyObject {
    func impulseBodies() -> [ImpulseBody]
    func applyBodyImpulse(_ impulse: BodyImpulse)
}

/// What the frame step reads and changes.
@MainActor
public protocol ImpulseWorld: ImpulseBodyWorld {
    func impulseActors() -> [MeleeTarget]
    /// The water surface height here, or nil where there is none.
    func waterHeight(at position: SIMD2<Float>) -> Float?
    /// The water current at a point under a surface, game units per second.
    func waterCurrent(at point: SIMD3<Float>) -> SIMD3<Float>?
    /// Water of a `WATR` with flag 0x1, where nothing splashes.
    func isDangerousWater(at point: SIMD3<Float>) -> Bool
    /// RACE size: 0 small, 1 normal, 2 large, 3 very large.
    func raceSize(of actor: ReferenceKey) -> Int
    /// False for an actor whose race is "Not Pushable": a hit does not knock it back.
    func isPushable(_ actor: ReferenceKey) -> Bool
    /// Pushes an actor along the ground. False when it cannot be pushed.
    @discardableResult
    func knockActor(_ actor: ReferenceKey, velocity: SIMD3<Float>, knockdown: Bool) -> Bool
    /// Knocks an actor down, away from `source`, with `magnitude` in Havok metres a second.
    @discardableResult
    func knockDown(_ actor: ReferenceKey, from source: SIMD3<Float>, magnitude: Float) -> Bool
    func actorHealth(of actor: ReferenceKey) -> (current: Float, maximum: Float)?
    @discardableResult
    func applyPhysicsDamage(_ amount: Float, to actor: ReferenceKey) -> Bool
    func showSplash(_ splash: SplashEvent)
    /// The actors and bodies that stand in water this frame, at the surface.
    func waterContacts(_ contacts: [WaterSample])
    /// Plays the sound of a loose body hitting something.
    func playCollision(_ collision: BodyCollision)
}

extension ImpulseWorld {
    public func waterContacts(_: [WaterSample]) {}
    public func playCollision(_: BodyCollision) {}
}

/// What set a push off, for the readout.
nonisolated public enum ImpulseCause: String, Equatable, Sendable {
    case melee, ranged, explosion, projectile, water, debug
}

/// One push, splash, or physics hit, kept for the readout.
nonisolated public enum ImpulseEvent: Equatable, Sendable {
    case knock(ReferenceKey, speed: Float, knockdown: Bool, cause: ImpulseCause)
    case push(ReferenceKey, impulse: Float, cause: ImpulseCause)
    case splash(SplashEvent)
    case physicsDamage(body: ReferenceKey, actor: ReferenceKey, damage: Float)
    case collision(BodyCollision)
}

@MainActor
public final class ImpulseRuntime {
    public static let eventLimit = 12

    public weak var world: (any ImpulseWorld)?
    public var settings: ImpulseSettings
    public var water: WaterImpactSettings
    public private(set) var events: [ImpulseEvent] = []
    public private(set) var splashCount = 0
    private var splashes = SplashTracker()
    /// Body and actor pairs in contact, so one strike hurts once.
    private var touching: Set<[ReferenceKey]> = []
    /// Actors that fast water knocked down and that have not left it yet.
    private var inFastWater: Set<ReferenceKey> = []
    private var collisions = BodyCollisionTracker()

    public init(
        settings: ImpulseSettings = .vanilla,
        water: WaterImpactSettings = .vanilla,
        world: (any ImpulseWorld)? = nil
    ) {
        self.settings = settings
        self.water = water
        self.world = world
    }

    public func advance(deltaTime: Float = 0) {
        guard let world else { return }
        let actors = world.impulseActors()
        let bodies = world.impulseBodies()
        splash(actors: actors, bodies: bodies, deltaTime: deltaTime, world: world)
        strike(actors: actors, bodies: bodies, world: world)
        for collision in collisions.update(bodies) {
            world.playCollision(collision)
            record(.collision(collision))
        }
        knockInFastWater(actors, world: world)
    }

    /// Notes a push another runtime made, for the readout.
    public func record(_ event: ImpulseEvent) {
        events.append(event)
        if events.count > Self.eventLimit {
            events.removeFirst(events.count - Self.eventLimit)
        }
    }

    /// Shows and logs a splash.
    public func play(_ splash: SplashEvent) {
        splashCount += 1
        world?.showSplash(splash)
        record(.splash(splash))
    }

    private func splash(
        actors: [MeleeTarget], bodies: [ImpulseBody], deltaTime: Float, world: any ImpulseWorld
    ) {
        let samples = actors.map { actor in
            WaterSample(
                key: actor.key, position: actor.feet, mass: nil,
                waterHeight: world.waterHeight(at: SIMD2(actor.feet.x, actor.feet.y))
            )
        } + bodies.map { body in
            WaterSample(
                key: body.key, position: body.position, mass: body.mass,
                waterHeight: world.waterHeight(at: SIMD2(body.position.x, body.position.y)),
                verticalSpeed: body.velocity.z
            )
        }
        for event in splashes.update(samples, deltaTime: deltaTime, settings: water)
            where !world.isDangerousWater(at: event.position)
        {
            play(event)
        }
        world.waterContacts(samples.filter(\.isWading))
    }

    private func strike(actors: [MeleeTarget], bodies: [ImpulseBody], world: any ImpulseWorld) {
        var nowTouching: Set<[ReferenceKey]> = []
        for body in bodies {
            let speed = simd_length(body.velocity)
            let damage = PhysicsDamage.damage(mass: body.mass, speed: speed, settings: settings)
            guard damage > 0 else { continue }
            for actor in actors where Self.touches(body, actor) {
                let pair = [body.key, actor.key]
                nowTouching.insert(pair)
                guard !touching.contains(pair), world.applyPhysicsDamage(damage, to: actor.key)
                else { continue }
                record(.physicsDamage(body: body.key, actor: actor.key, damage: damage))
            }
        }
        touching = nowTouching
    }

    private func knockInFastWater(_ actors: [MeleeTarget], world: any ImpulseWorld) {
        var stillIn: Set<ReferenceKey> = []
        for actor in actors {
            guard
                let current = world.waterCurrent(at: actor.feet),
                WaterImpacts.knocksDown(
                    flowSpeed: simd_length(SIMD2(current.x, current.y)) / WaterImpacts.havokScale,
                    raceSize: world.raceSize(of: actor.key), settings: water
                )
            else { continue }
            let flow = SIMD2(current.x, current.y)
            stillIn.insert(actor.key)
            guard !inFastWater.contains(actor.key) else { continue }
            let velocity = SIMD3(flow.x, flow.y, 0)
            if world.knockActor(actor.key, velocity: velocity, knockdown: true) {
                record(.knock(
                    actor.key, speed: simd_length(flow), knockdown: true, cause: .water
                ))
            }
        }
        inFastWater = stillIn
    }

    static func touches(_ body: ImpulseBody, _ actor: MeleeTarget) -> Bool {
        let (first, second) = actor.segment
        let near = DynamicCollisionMath.closestPoint(
            onSegment: (first, second), to: body.position
        )
        let reach = actor.capsule.radius + body.boundingRadius
        return simd_distance_squared(near, body.position) <= reach * reach
    }
}
