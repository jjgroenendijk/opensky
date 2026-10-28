// Flies every loaded dragon nobody rides: it follows the fight's air, perch, and ground
// stages, a forced take-off or landing, and the landings Dragonrend, injury, and death
// ask for. The rules live in `DragonFlightRules`; the player's ridden dragon flies in its
// mount drive. See docs/engine/dragon-flight.md.

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
    /// Health below its race's injured share (`GetIsInjured`).
    public var isInjured = false
    /// Its `DragonRend` actor value is above 0.
    public var isRended = false
    /// It died in the air and still has to come down.
    public var isDead = false

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
    /// The perches in the loaded cells.
    func dragonPerches() -> [DragonPerch]
    /// The landing event the `ActionFlyStop` idle tree picks, testing the perch as the
    /// Target. Nil when no tree is loaded.
    func landingEvent(for actor: ReferenceKey, perch: ReferenceKey?) -> String?
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
    /// Land on the nearest perch in reach, or hover where none is.
    case perch
    case hastyLand
    case crashLand

    /// Orders that end once the dragon is on the ground or its perch.
    var endsOnLanding: Bool {
        self != .takeOff
    }
}

@MainActor
public final class DragonFlightCoordinator {
    public private(set) var flights: [ReferenceKey: DragonFlightState] = [:]
    public private(set) var orders: [ReferenceKey: DragonFlightOrder] = [:]
    /// Where a forced flight circles: the point it took off from.
    private var homes: [ReferenceKey: SIMD3<Float>] = [:]
    /// Wing dust and touchdowns acted on, for the readout.
    public private(set) var handledEvents = 0
    /// The landing event each landing dragon's graph got, for the readout.
    public private(set) var landingEvents: [ReferenceKey: String] = [:]
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

    /// The landing each actor was asked for, for `GetIsHastyLandRequest` and
    /// `GetIsCrashLandRequest`.
    public var landingRequests: [ReferenceKey: DragonLandingRequest] {
        flights.compactMapValues { $0.landingRequest == .none ? nil : $0.landingRequest }
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
        let perches = world.dragonPerches()
        for candidate in candidates where !candidate.isRidden {
            fly(candidate, perches: perches, deltaTime: deltaTime, world: world)
        }
        orders = orders.filter { present.contains($0.key) }
    }

    /// Acts on a dragon clip event. True when the engine reads `name`.
    @discardableResult
    public func handle(_ name: String, from actor: ReferenceKey) -> Bool {
        typealias Names = DragonFlightGraphNames
        let matches: (String) -> Bool = { $0.caseInsensitiveCompare(name) == .orderedSame }
        guard let event = Names.observedEvents.first(where: matches) else { return false }
        handledEvents += 1
        guard let world, let state = flights[actor] else { return true }
        let below = SIMD2(state.feet.x, state.feet.y)
        let floor = world.flightGroundHeight(at: below) ?? state.feet.z
        switch event {
        case Names.landingEffect:
            world.playLandingDust(actor, at: SIMD3(below, floor))
        case Names.forcefulLandStart, Names.crashLandStart, Names.crashLandEnd:
            guard state.phase == .landing, state.perch == nil else { break }
            touchDown(actor, state: state, floor: floor, world: world)
        default:
            break
        }
        return true
    }

    // MARK: - Flying

    private func fly(
        _ candidate: DragonFlightCandidate, perches: [DragonPerch], deltaTime: Float,
        world: any DragonFlightWorld
    ) {
        let key = candidate.key
        let goal = goal(for: candidate, perches: perches)
        var state = flights[key] ?? DragonFlightState(feet: candidate.feet, yaw: candidate.yaw)
        if state.phase == .grounded {
            guard goal.isAirborne, !candidate.isDead, let hold = world.holdForFlight(key) else {
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
        // Stored first, so the landing tree's request conditions read this step.
        flights[key] = step.state
        for event in step.events {
            if let name = graphEvent(for: event, state: step.state, of: key, world: world) {
                world.raiseFlightEvent(name, on: key)
            }
        }
        world.moveFlying(
            key, state: step.state,
            inputs: DragonFlightGraphNames.inputs(step.state, settings: settings)
        )
        if !step.state.phase.isFlying {
            land(key, world: world)
        }
    }

    /// The approach event comes from the landing idle tree; the rest are fixed.
    private func graphEvent(
        for event: DragonFlightEvent, state: DragonFlightState, of actor: ReferenceKey,
        world: any DragonFlightWorld
    ) -> String? {
        guard event == .beginApproach else { return DragonFlightGraphNames.event(for: event) }
        let name = world.landingEvent(for: actor, perch: state.perch?.reference)
            ?? DragonFlightGraphNames.landingEvent(for: state.landingRequest)
        landingEvents[actor] = name
        return name
    }

    /// Death, Dragonrend, the forced order, then the fight. Without any the dragon lands.
    func goal(
        for candidate: DragonFlightCandidate, perches: [DragonPerch] = []
    ) -> DragonFlightGoal {
        if candidate.isDead {
            return .ground(nil, .crash)
        }
        if candidate.isRended {
            return .ground(nil, .hasty)
        }
        if let order = orders[candidate.key] {
            return goal(for: candidate, order: order, perches: perches)
        }
        guard candidate.isAllowedToFly, candidate.canFlyHere, let target = candidate.target
        else { return .ground(nil) }
        let landing = DragonFlightGoal.ground(Self.landingPoint(near: target, from: candidate.feet))
        if candidate.isInjured, candidate.fight != nil {
            return landing
        }
        switch candidate.fight {
        case .air: return .circle(center: target, radius: candidate.orbitRadius)
        case .perch:
            let perch = DragonPerchRules.choose(perches, target: target, settings: settings)
            return perch.map(DragonFlightGoal.perch) ?? .hover(facing: target)
        case .ground: return landing
        case nil: return .ground(nil)
        }
    }

    private func goal(
        for candidate: DragonFlightCandidate, order: DragonFlightOrder, perches: [DragonPerch]
    ) -> DragonFlightGoal {
        let home = homes[candidate.key] ?? candidate.feet
        switch order {
        case .takeOff: return .circle(center: home, radius: candidate.orbitRadius)
        case .land: return .ground(nil)
        case .hastyLand: return .ground(nil, .hasty)
        case .crashLand: return .ground(nil, .crash)
        case .perch:
            let perch = DragonPerchRules.nearest(perches, to: candidate.feet, settings: settings)
            return perch.map(DragonFlightGoal.perch) ?? .hover(facing: home)
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
        landingEvents[actor] = nil
        homes[actor] = nil
        finishOrder(of: actor)
        world.releaseFromFlight(actor)
    }

    private func finishOrder(of actor: ReferenceKey) {
        if orders[actor]?.endsOnLanding == true {
            orders[actor] = nil
        }
    }

    /// An actor that unloaded in the air drops to the ground under it.
    private func drop(_ actor: ReferenceKey, world: any DragonFlightWorld) {
        guard let state = flights[actor] else { return }
        let floor = world.flightGroundHeight(at: SIMD2(state.feet.x, state.feet.y))
        touchDown(actor, state: state, floor: floor ?? state.feet.z, world: world)
    }
}
