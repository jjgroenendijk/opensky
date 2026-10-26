// The rules of a dragon's flight: the take-off, the circle around a centre, the hover,
// and the landing. Pure; `DragonFlightCoordinator` and the player's mount drive are the
// shells. See docs/engine/dragon-flight.md.

import Foundation
import OpenSkyFormatsESM
import simd

/// The `GetFlyingState` values (<https://ck.uesp.net/wiki/GetFlyingState_-_Actor>).
/// 5, perched on a word wall or a rock, is not modelled.
nonisolated public enum DragonFlightPhase: Int32, Equatable, Sendable, CaseIterable {
    case grounded = 0
    case takingOff = 1
    case cruising = 2
    case hovering = 3
    case landing = 4

    /// `GetIsFlying`: 1 until the landing is done.
    public var isFlying: Bool {
        self != .grounded
    }
}

/// Where a dragon wants to be.
nonisolated public enum DragonFlightGoal: Equatable, Sendable {
    /// On the ground: at the point, or ahead of where it flies when nil.
    case ground(SIMD3<Float>?)
    case circle(center: SIMD3<Float>, radius: Float)
    /// Still in the air, turned toward the point.
    case hover(facing: SIMD3<Float>)

    public var isAirborne: Bool {
        if case .ground = self {
            return false
        }
        return true
    }
}

/// The flight numbers. Speeds and turns are the vanilla dragon movement types and the
/// times the clip lengths of `mttakeoff45` and `mtland45approach`; the rest are OpenSky's.
nonisolated public struct DragonFlightSettings: Equatable, Sendable {
    /// Units per second: `Dragon_Flying_MT` forward walk.
    public var cruiseSpeed: Float = 2000
    /// Radians per second: `Dragon_Flying_MT` rotate in place.
    public var turnRate: Float = .pi / 2
    /// Radians per second: `Dragon_Hovering_MT` rotate in place.
    public var hoverTurnRate: Float = .pi / 4
    /// Height above the ground under the dragon while it circles.
    public var cruiseHeight: Float = 1500
    public var hoverHeight: Float = 700
    /// Units per second, up or down.
    public var climbRate: Float = 500
    public var takeOffSeconds: Float = 5
    /// The landing approach clip: the graph lands this long after `FlyStopDefault`.
    public var approachSeconds: Float = 10 / 3
    /// The slowest a landing approach flies, so the last stretch still ends.
    public var landingSpeed: Float = 300
    /// How far ahead of the dragon, in radians round the circle, it steers.
    public var circleLead: Float = 0.6

    public static let standard = Self()

    public init() {}

    public static let flyingType = "Dragon_Flying_MT"
    public static let hoveringType = "Dragon_Hovering_MT"

    /// The vanilla numbers, with the speeds and turns of the load order's dragon types.
    public static func resolve(movementTypes: MovementTypeStore) -> Self {
        var settings = Self.standard
        if let flying = movementTypes.type(editorID: flyingType)?.speeds {
            settings.cruiseSpeed = flying.forwardWalk
            settings.turnRate = flying.rotateInPlaceWalk
        }
        if let hovering = movementTypes.type(editorID: hoveringType)?.speeds {
            settings.hoverTurnRate = hovering.rotateInPlaceWalk
        }
        return settings
    }

    /// Speed gained or lost per second.
    public var acceleration: Float {
        cruiseSpeed / 2
    }
}

nonisolated public struct DragonFlightState: Equatable, Sendable {
    public var phase: DragonFlightPhase
    public var feet: SIMD3<Float>
    /// Walk yaw, counter-clockwise from +X.
    public var yaw: Float
    /// Horizontal speed, units per second.
    public var speed: Float = 0
    public var verticalSpeed: Float = 0
    /// The climb angle change of the last step, radians.
    public var pitchDelta: Float = 0
    public var phaseSeconds: Float = 0
    public var landingPoint: SIMD3<Float>?
    /// The graph plays its approach clip; the landing can no longer be cancelled.
    public var isApproaching = false
    /// The last ground height known, for where the ground has no height.
    public var lastGround: Float?

    public init(feet: SIMD3<Float>, yaw: Float, phase: DragonFlightPhase = .grounded) {
        self.feet = feet
        self.yaw = yaw
        self.phase = phase
    }

    /// The climb angle, radians; positive climbs.
    public var pitch: Float {
        atan2(verticalSpeed, max(speed, 1))
    }

    /// Up or down share of the move direction, -1 to 1.
    public var moveDirectionZ: Float {
        let length = simd_length(SIMD2(speed, verticalSpeed))
        return length > 0.001 ? verticalSpeed / length : 0
    }
}

/// What a step asks of the dragon's graph.
nonisolated public enum DragonFlightEvent: Equatable, Sendable {
    case takeOff
    case startHover
    case stopHover
    case beginLanding
    case cancelLanding
    /// Close enough that the approach clip ends at the landing point.
    case beginApproach
    case landed
}

nonisolated public struct DragonFlightStep: Equatable, Sendable {
    public var state: DragonFlightState
    public var events: [DragonFlightEvent]
}

/// The ground height under a point, or nil where no ground is known.
public typealias DragonGroundHeight = (SIMD2<Float>) -> Float?

nonisolated public enum DragonFlightRules {
    /// A dragon this close to its landing point, in units, has arrived.
    public static let arrivalDistance: Float = 8

    public static func step(
        _ state: DragonFlightState, goal: DragonFlightGoal, settings: DragonFlightSettings,
        deltaTime: Float, ground: @escaping DragonGroundHeight
    ) -> DragonFlightStep {
        guard deltaTime.isFinite, deltaTime > 0 else {
            return DragonFlightStep(state: state, events: [])
        }
        var flight = Flight(
            state: state, settings: settings, deltaTime: deltaTime, ground: ground
        )
        flight.state.phaseSeconds += deltaTime
        let pitch = state.pitch
        flight.advance(toward: goal)
        flight.state.pitchDelta = flight.state.phase.isFlying ? flight.state.pitch - pitch : 0
        return DragonFlightStep(state: flight.state, events: flight.events)
    }

    /// The point on the circle the dragon steers at: ahead of it, counter-clockwise.
    public static func circlePoint(
        from position: SIMD2<Float>, yaw: Float, center: SIMD2<Float>, radius: Float,
        lead: Float
    ) -> SIMD2<Float> {
        let offset = position - center
        let angle = simd_length(offset) > 1 ? atan2(offset.y, offset.x) : yaw
        return center + SIMD2(cos(angle + lead), sin(angle + lead)) * max(radius, 0)
    }

    /// The turn from `yaw` toward `target`, at most `limit` either way.
    public static func turn(from yaw: Float, toward target: Float, limit: Float) -> Float {
        let wanted = remainder(target - yaw, 2 * Float.pi)
        return remainder(yaw + min(max(wanted, -limit), limit), 2 * Float.pi)
    }
}

/// One step's working state.
nonisolated private struct Flight {
    var state: DragonFlightState
    let settings: DragonFlightSettings
    let deltaTime: Float
    let ground: DragonGroundHeight
    var events: [DragonFlightEvent] = []

    mutating func groundHeight(at point: SIMD2<Float>) -> Float {
        if let height = ground(point) {
            state.lastGround = height
            return height
        }
        return state.landingPoint?.z ?? state.lastGround ?? state.feet.z
    }

    var position: SIMD2<Float> {
        SIMD2(state.feet.x, state.feet.y)
    }

    mutating func advance(toward goal: DragonFlightGoal) {
        switch state.phase {
        case .grounded:
            guard goal.isAirborne else { return }
            state.lastGround = groundHeight(at: position)
            enter(.takingOff, raising: .takeOff)
            state.verticalSpeed = 0
        case .takingOff: takeOff(goal)
        case .cruising: cruise(goal)
        case .hovering: hover(goal)
        case .landing: land(goal)
        }
    }

    mutating func enter(_ phase: DragonFlightPhase, raising event: DragonFlightEvent?) {
        state.phase = phase
        state.phaseSeconds = 0
        if let event {
            events.append(event)
        }
    }

    private mutating func takeOff(_ goal: DragonFlightGoal) {
        guard goal.isAirborne else { return beginLanding(goal) }
        let share = min(state.phaseSeconds / max(settings.takeOffSeconds, 0.01), 1)
        let height = groundHeight(at: position) + settings.cruiseHeight
        move(heading: state.yaw, speed: settings.cruiseSpeed * share * share, height: height)
        guard state.phaseSeconds >= settings.takeOffSeconds else { return }
        if case .hover = goal {
            enter(.hovering, raising: .startHover)
        } else {
            enter(.cruising, raising: nil)
        }
    }

    private mutating func cruise(_ goal: DragonFlightGoal) {
        switch goal {
        case .ground: beginLanding(goal)
        case .hover: enter(.hovering, raising: .startHover)
        case let .circle(center, radius):
            let point = DragonFlightRules.circlePoint(
                from: position, yaw: state.yaw, center: SIMD2(center.x, center.y),
                radius: radius, lead: settings.circleLead
            )
            let height = max(groundHeight(at: position), center.z) + settings.cruiseHeight
            move(toward: point, speed: settings.cruiseSpeed, height: height)
        }
    }

    private mutating func hover(_ goal: DragonFlightGoal) {
        switch goal {
        case .ground:
            events.append(.stopHover)
            beginLanding(goal)
        case .circle: enter(.cruising, raising: .stopHover)
        case let .hover(facing):
            let wanted = atan2(facing.y - state.feet.y, facing.x - state.feet.x)
            state.yaw = DragonFlightRules.turn(
                from: state.yaw, toward: wanted, limit: settings.hoverTurnRate * deltaTime
            )
            let height = groundHeight(at: position) + settings.hoverHeight
            move(heading: state.yaw, speed: 0, height: height)
        }
    }

    private mutating func beginLanding(_ goal: DragonFlightGoal) {
        let ahead = position + SIMD2(cos(state.yaw), sin(state.yaw)) * state.speed * 1.5
        var point = SIMD3(ahead.x, ahead.y, 0)
        if case let .ground(.some(wanted)) = goal {
            point = wanted
        }
        point.z = groundHeight(at: SIMD2(point.x, point.y))
        state.landingPoint = point
        enter(.landing, raising: .beginLanding)
    }

    private mutating func land(_ goal: DragonFlightGoal) {
        guard let target = state.landingPoint, state.isApproaching || !goal.isAirborne else {
            state.landingPoint = nil
            return enter(.cruising, raising: .cancelLanding)
        }
        let offset = SIMD2(target.x, target.y) - position
        let distance = simd_length(offset)
        let speed = min(settings.cruiseSpeed, max(settings.landingSpeed, distance * 0.5))
        let height = target.z + min(settings.cruiseHeight, distance * 0.4)
        move(toward: SIMD2(target.x, target.y), speed: speed, height: height, stopsAt: true)
        let left = simd_length(SIMD2(target.x, target.y) - position)
        let secondsLeft = max(
            left / max(state.speed, settings.landingSpeed),
            (state.feet.z - target.z) / max(settings.climbRate, 1)
        )
        if !state.isApproaching, secondsLeft <= settings.approachSeconds {
            state.isApproaching = true
            events.append(.beginApproach)
        }
        guard
            left <= DragonFlightRules.arrivalDistance,
            state.feet.z - target.z <= DragonFlightRules.arrivalDistance
        else { return }
        state.feet = SIMD3(state.feet.x, state.feet.y, groundHeight(at: position))
        state.speed = 0
        state.verticalSpeed = 0
        state.landingPoint = nil
        state.isApproaching = false
        enter(.grounded, raising: .landed)
    }

    private mutating func move(
        toward point: SIMD2<Float>, speed: Float, height: Float, stopsAt: Bool = false
    ) {
        let offset = point - position
        guard simd_length(offset) > 0.001 else {
            return move(heading: state.yaw, speed: 0, height: height)
        }
        let wanted = atan2(offset.y, offset.x)
        state.yaw = DragonFlightRules.turn(
            from: state.yaw, toward: wanted, limit: settings.turnRate * deltaTime
        )
        guard stopsAt else { return move(heading: state.yaw, speed: speed, height: height) }
        let limit = simd_length(offset) / deltaTime
        move(
            heading: wanted, speed: min(speed, limit), height: height, capsSpeed: true
        )
    }

    /// Eases the speed toward `speed`, moves along `heading`, and climbs or sinks toward
    /// `height`. A landing approach moves straight at its point while the body turns, so
    /// the turn limit cannot keep it circling, and never overshoots.
    private mutating func move(
        heading: Float, speed: Float, height: Float, capsSpeed: Bool = false
    ) {
        let change = settings.acceleration * deltaTime
        state.speed = min(max(speed, state.speed - change), state.speed + change)
        if capsSpeed {
            state.speed = min(state.speed, speed)
        }
        let step = SIMD2(cos(heading), sin(heading)) * state.speed * deltaTime
        let rise = min(
            max(height - state.feet.z, -settings.climbRate * deltaTime),
            settings.climbRate * deltaTime
        )
        state.verticalSpeed = rise / deltaTime
        let next = position + step
        let floor = groundHeight(at: next)
        state.feet = SIMD3(next.x, next.y, max(state.feet.z + rise, floor))
    }
}
