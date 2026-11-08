public import OpenSkyWorldInterface

/// What the world adapters use of `DragonFlightState`.
public protocol DragonFlightStatePort {
    var perch: DragonPerch? { get }
    var phase: DragonFlightPhase { get }

    var feet: SIMD3<Float> { get }
    var isApproaching: Bool { get set }
    var landingPoint: SIMD3<Float>? { get }
    var landingRequest: DragonLandingRequest { get set }
    var pitch: Float { get }
    var speed: Float { get }
    var verticalSpeed: Float { get }
    var yaw: Float { get }
}
