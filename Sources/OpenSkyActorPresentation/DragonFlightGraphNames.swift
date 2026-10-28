// The dragon graph names flight raises, reads, and writes. Read from
// `dragonbehavior.hkx` and the dragon clips on the install (docs/engine/dragon-flight.md).

import Foundation
import OpenSkyBehavior
import simd

nonisolated public enum DragonFlightGraphNames {
    /// Moves the graph from the ground into the take-off clip, which ends in cruising.
    public static let takeOff = "TakeOff"
    /// Moves the cruising graph into the approach clip; it then touches down by itself.
    public static let land = "FlyStopDefault"
    public static let hoverStart = "HoverStart"
    public static let hoverStop = "HoverStop"
    /// The idle action whose tree picks the landing event: a perch by its furniture,
    /// then the hasty, crash, and injured landings (`FlyStopRootDragon`).
    public static let landingAction = "ActionFlyStop"
    public static let hastyLanding = "FlyStopHasty"
    public static let crashLanding = "FlyStopCrash"

    /// Moves the flying graph into the breath's inhale clip.
    public static let breathStart = "shoutStart"
    /// Moves the inhale into the exhale, whose `Voice_SpellFire_Event` casts the breath.
    public static let breathRelease = "shoutRelease"
    public static let breathFire = "Voice_SpellFire_Event"

    /// Wing beats of the landing approach clips, close over the ground.
    public static let landingEffect = "FlightLandingEffect"
    /// On the crash approach clips, before the crash.
    public static let crashLandLoadEffect = "FlightCrashLandLoadEffect"
    /// The feet touch the ground in a vertical or short crash landing.
    public static let forcefulLandStart = "FlightForcefulLandStart"
    /// The body touches the ground in a long crash landing.
    public static let crashLandStart = "FlightCrashLandStart"
    /// The long crash slide ends.
    public static let crashLandEnd = "FlightCrashLandEnd"

    /// The clip events the engine reacts to; `openskycli gaps` counts them as done.
    public static let observedEvents = [
        landingEffect, crashLandLoadEffect, forcefulLandStart, crashLandStart, crashLandEnd
    ]

    public static let targetSpeed = "TargetSpeed"
    public static let pitchDelta = "PitchDelta"
    public static let moveDirectionZ = "MoveDirZ"
    public static let distanceToGoal = "DistToGoal"
    /// Bound to `BSTweenerModifier.targetPosition`, a world position.
    public static let tweenPosition = "TweenPosition"
    /// Bound to `BSTweenerModifier.targetRotation`, a world rotation.
    public static let tweenRotation = "TweenRotation"
    public static let isOnGround = "IsOnGround"

    /// The rider's graph: how far the mount's climb tilts the rider's aim, radians.
    public static let riderPitchOffset = "PitchOffset"

    /// Every variable flight writes, the rider's included.
    public static let variables = [
        targetSpeed, pitchDelta, moveDirectionZ, distanceToGoal, tweenPosition, tweenRotation,
        isOnGround, riderPitchOffset
    ]

    /// `DistToGoal` with no landing point: farther than any test in the graph.
    public static let noGoalDistance: Float = 100_000

    /// The graph event for one step event.
    public static func event(for flight: DragonFlightEvent) -> String? {
        switch flight {
        case .takeOff: takeOff
        case .startHover: hoverStart
        case .stopHover: hoverStop
        case .beginApproach: land
        case .beginLanding, .cancelLanding, .landed, .perched: nil
        }
    }

    /// The landing event when no idle tree picks one.
    public static func landingEvent(for request: DragonLandingRequest) -> String {
        switch request {
        case .none: land
        case .hasty: hastyLanding
        case .crash: crashLanding
        }
    }

    /// The variables one flight step writes, in write order. A target speed is the
    /// cruise speed in the air and 0 on the ground.
    public static func inputs(
        _ state: DragonFlightState, settings: DragonFlightSettings
    ) -> [(name: String, value: BehaviorVariableValue)] {
        let goal = state.landingPoint ?? state.feet
        let distance = state.landingPoint.map { simd_distance($0, state.feet) } ?? noGoalDistance
        let target: Float = switch state.phase {
        case .grounded, .hovering, .perched: 0
        case .takingOff, .cruising: settings.cruiseSpeed
        case .landing: settings.landingSpeed
        }
        let heading = Float.pi / 2 - state.yaw
        let rotation = ActorGraphCore.worldRotation(placementRotationZ: heading)
        return [
            (targetSpeed, .real(target)),
            (pitchDelta, .real(state.pitchDelta)),
            (moveDirectionZ, .real(state.moveDirectionZ)),
            (distanceToGoal, .real(distance)),
            (tweenPosition, .quad(SIMD4(goal, 0))),
            (tweenRotation, .quad(rotation.vector)),
            (isOnGround, .bool(state.phase == .grounded || state.phase == .perched))
        ]
    }
}
