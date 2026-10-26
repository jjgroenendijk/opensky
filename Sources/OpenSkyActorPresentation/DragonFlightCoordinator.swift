// Flies every loaded dragon nobody rides: it follows the fight's air, perch, and ground
// stages, or a forced take-off or landing. The rules live in `DragonFlightRules`; the
// player's ridden dragon flies in its mount drive. See docs/engine/dragon-flight.md.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsESM
import simd

/// The stage of a flying actor's fight, as the combat loop picked it.
nonisolated public enum DragonFightStage: String, Equatable, Sendable {
    case air
    case perch
    case ground
}

/// One loaded, living actor whose race flies.
nonisolated public struct DragonFlightCandidate: Equatable, Sendable {
    public let key: ReferenceKey
    public let feet: SIMD3<Float>
    /// Walk yaw, counter-clockwise from +X.
    public let yaw: Float
    /// Nil when it is not fighting.
    public var fight: DragonFightStage?
    /// The feet of whoever it fights.
    public var target: SIMD3<Float>?
    public var orbitRadius: Float = 4000
    /// `SetAllowFlying`; true until a script says otherwise.
    public var isAllowedToFly = true
    /// False in an interior, where no dragon flies.
    public var canFlyHere = true
    /// The player rides it, so the mount drive flies it.
    public var isRidden = false

    public init(key: ReferenceKey, feet: SIMD3<Float>, yaw: Float) {
        self.key = key
        self.feet = feet
        self.yaw = yaw
    }
}

/// What the dragon flight coordinator reads from and does to the session.
@MainActor
public protocol DragonFlightWorld: AnyObject {
    /// The load order's flight numbers, read once.
    var dragonFlightSettings: DragonFlightSettings { get }
    func dragonFlightCandidates() -> [DragonFlightCandidate]
    /// Takes the actor from its packages and mover. Nil when it cannot be held.
    func holdForFlight(_ actor: ReferenceKey) -> (feet: SIMD3<Float>, yaw: Float)?
    /// Moves the held actor and writes its graph's flight inputs.
    func moveFlying(
        _ actor: ReferenceKey, state: DragonFlightState,
        inputs: [(name: String, value: BehaviorVariableValue)]
    )
    /// Gives the actor back to its packages and mover where it stands.
    func releaseFromFlight(_ actor: ReferenceKey)
    func flightGroundHeight(at point: SIMD2<Float>) -> Float?
    func raiseFlightEvent(_ name: String, on actor: ReferenceKey)
    /// The wing dust of a landing approach, on the ground at `point`.
    func playLandingDust(_ actor: ReferenceKey, at point: SIMD3<Float>)
}

/// A forced flight from agent control, which wins over the fight.
nonisolated public enum DragonFlightOrder: String, Equatable, Sendable {
    case takeOff
    case land
}

@MainActor
public final class DragonFlightCoordinator {
    public private(set) var flights: [ReferenceKey: DragonFlightState] = [:]
    public private(set) var orders: [ReferenceKey: DragonFlightOrder] = [:]
    /// Where a forced flight circles: the point it took off from.
    private var homes: [ReferenceKey: SIMD3<Float>] = [:]
    /// Wing dust and touchdowns acted on, for the readout.
    public private(set) var handledEvents = 0
    public let settings: DragonFlightSettings
    weak let world: (any DragonFlightWorld)?

    public init(world: any DragonFlightWorld) {
        self.world = world
        settings = world.dragonFlightSettings
    }

    /// `GetFlyingState` of a dragon nobody rides.
    public func phase(of actor: ReferenceKey) -> DragonFlightPhase {
        flights[actor]?.phase ?? .grounded
    }

    /// Every actor in the air, for `GetIsFlying`.
    public var flyingActors: Set<ReferenceKey> {
        Set(flights.filter(\.value.phase.isFlying).keys)
    }

    /// Forces a take-off or a landing. A landing order ends once the dragon is down.
    public func order(_ order: DragonFlightOrder, for actor: ReferenceKey) {
        orders[actor] = order
    }

    public func tick(deltaTime: Float) {
        guard let world, deltaTime > 0 else { return }
        let candidates = world.dragonFlightCandidates().sorted { $0.key < $1.key }
        let present = Set(candidates.map(\.key))
        for key in flights.keys.sorted() where !present.contains(key) {
            drop(key, world: world)
        }
        for candidate in candidates where !candidate.isRidden {
            fly(candidate, deltaTime: deltaTime, world: world)
        }
        orders = orders.filter { present.contains($0.key) }
    }

    /// Acts on a dragon clip event. True when the engine reads `name`.
    @discardableResult
    public func handle(_ name: String, from actor: ReferenceKey) -> Bool {
        typealias Names = DragonFlightGraphNames
        guard let event = Names.observedEvents.first(where: {
            $0.caseInsensitiveCompare(name) == .orderedSame
        }) else { return false }
        handledEvents += 1
        guard let world, let state = flights[actor] else { return true }
        let below = SIMD2(state.feet.x, state.feet.y)
        let floor = world.flightGroundHeight(at: below) ?? state.feet.z
        switch event {
        case Names.landingEffect:
            world.playLandingDust(actor, at: SIMD3(below, floor))
        case Names.forcefulLandStart, Names.crashLandStart, Names.crashLandEnd:
            guard state.phase == .landing else { break }
            touchDown(actor, state: state, floor: floor, world: world)
        default:
            break
        }
        return true
    }

    // MARK: - Flying

    private func fly(
        _ candidate: DragonFlightCandidate, deltaTime: Float, world: any DragonFlightWorld
    ) {
        let key = candidate.key
        let goal = goal(for: candidate)
        var state = flights[key] ?? DragonFlightState(feet: candidate.feet, yaw: candidate.yaw)
        if state.phase == .grounded {
            guard goal.isAirborne, let hold = world.holdForFlight(key) else {
                finishOrder(of: key)
                return
            }
            state = DragonFlightState(feet: hold.feet, yaw: hold.yaw)
            homes[key] = hold.feet
        }
        let step = DragonFlightRules.step(
            state, goal: goal, settings: settings, deltaTime: deltaTime,
            ground: { [weak world] in world?.flightGroundHeight(at: $0) }
        )
        for event in step.events {
            if let name = DragonFlightGraphNames.event(for: event) {
                world.raiseFlightEvent(name, on: key)
            }
        }
        world.moveFlying(
            key, state: step.state,
            inputs: DragonFlightGraphNames.inputs(step.state, settings: settings)
        )
        guard step.state.phase.isFlying else {
            land(key, world: world)
            return
        }
        flights[key] = step.state
    }

    /// The forced order first, then the fight. Without either the dragon lands.
    func goal(for candidate: DragonFlightCandidate) -> DragonFlightGoal {
        let home = homes[candidate.key] ?? candidate.feet
        switch orders[candidate.key] {
        case .takeOff: return .circle(center: home, radius: candidate.orbitRadius)
        case .land: return .ground(nil)
        case nil: break
        }
        guard candidate.isAllowedToFly, candidate.canFlyHere, let target = candidate.target
        else { return .ground(nil) }
        switch candidate.fight {
        case .air: return .circle(center: target, radius: candidate.orbitRadius)
        case .perch: return .hover(facing: target)
        case .ground: return .ground(Self.landingPoint(near: target, from: candidate.feet))
        case nil: return .ground(nil)
        }
    }

    /// Lands beside the target rather than on it, on the side the dragon comes from.
    public static let landingDistance: Float = 600

    static func landingPoint(near target: SIMD3<Float>, from feet: SIMD3<Float>)
        -> SIMD3<Float>
    {
        let away = SIMD2(feet.x - target.x, feet.y - target.y)
        let length = simd_length(away)
        let direction = length > 1 ? away / length : SIMD2(1, 0)
        let point = SIMD2(target.x, target.y) + direction * landingDistance
        return SIMD3(point, target.z)
    }

    private func touchDown(
        _ actor: ReferenceKey, state: DragonFlightState, floor: Float,
        world: any DragonFlightWorld
    ) {
        var landed = state
        landed.feet.z = floor
        landed.phase = .grounded
        landed.speed = 0
        landed.verticalSpeed = 0
        landed.landingPoint = nil
        world.moveFlying(
            actor, state: landed, inputs: DragonFlightGraphNames.inputs(landed, settings: settings)
        )
        land(actor, world: world)
    }

    private func land(_ actor: ReferenceKey, world: any DragonFlightWorld) {
        flights[actor] = nil
        homes[actor] = nil
        finishOrder(of: actor)
        world.releaseFromFlight(actor)
    }

    private func finishOrder(of actor: ReferenceKey) {
        if orders[actor] == .land {
            orders[actor] = nil
        }
    }

    /// An actor that died or unloaded in the air drops to the ground under it.
    private func drop(_ actor: ReferenceKey, world: any DragonFlightWorld) {
        guard let state = flights[actor] else { return }
        let floor = world.flightGroundHeight(at: SIMD2(state.feet.x, state.feet.y))
        touchDown(actor, state: state, floor: floor ?? state.feet.z, world: world)
    }
}
