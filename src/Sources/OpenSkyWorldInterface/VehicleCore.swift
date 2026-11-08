import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyWorldState
public import simd

/// One follower's carrier and how it sits there.
nonisolated public struct VehicleLink: Equatable, Sendable {
    public let carrier: ReferenceKey
    public var seat: VehicleSeat

    public init(
        carrier: ReferenceKey,
        seat: VehicleSeat
    ) {
        self.carrier = carrier
        self.seat = seat
    }
}

/// How a follower sits on its carrier.
nonisolated public enum VehicleSeat: Equatable, Sendable {
    /// A fixed pose in the carrier's frame.
    case fixed(float4x4)
    /// On a bone of the carrier's live pose, such as a horse's `SaddleBone`.
    case bone(String)
    /// Pulled along the carrier's path, as a cart behind its horse.
    case towed(VehicleTow)
}

/// A towed follower keeps its distance to the carrier and turns toward it.
nonisolated public struct VehicleTow: Equatable, Sendable {
    /// Horizontal distance from the follower's origin to the carrier's origin.
    public let length: Float
    /// The follower's orientation at the link, and the heading of its own +Y axis then.
    /// Each frame it turns from that heading to face the carrier, so a cart placed a
    /// little off its horse's line lines up with it, as the harness pulls it in the game.
    public let orientation: float3x3
    public let linkHeading: Float
    public let linkSlope: Float
    /// Height above the carrier, used where no ground answers.
    public let rise: Float
    public var position: SIMD3<Float>
    public var heading: Float
    /// Where the wheels touch the ground, in the model frame; nil until the model loads.
    public var wheels: [SIMD2<Float>]?
    /// How far the follower has rolled forward since the link, for its wheels' spin.
    public var rolled: Float = 0
    /// The heading of the body, from the rear axle to the front one. Nil follows `heading`.
    public var bodyHeading: Float?
    public var turns = VehicleWheelTurns()

    public init(
        length: Float,
        orientation: float3x3,
        linkHeading: Float,
        linkSlope: Float,
        rise: Float,
        position: SIMD3<Float>,
        heading: Float,
        wheels: [SIMD2<Float>]? = nil,
        rolled: Float = 0,
        bodyHeading: Float? = nil,
        turns: VehicleWheelTurns = VehicleWheelTurns()
    ) {
        self.length = length
        self.orientation = orientation
        self.linkHeading = linkHeading
        self.linkSlope = linkSlope
        self.rise = rise
        self.position = position
        self.heading = heading
        self.wheels = wheels
        self.rolled = rolled
        self.bodyHeading = bodyHeading
        self.turns = turns
    }
}
