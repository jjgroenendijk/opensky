import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import simd

nonisolated public struct BodyCollision: Equatable, Sendable {
    public let body: ReferenceKey
    public let position: SIMD3<Float>
    /// Units per second the hit took off the body's velocity.
    public let speedLoss: Float
    public let material: FormID?
    /// What the body hit. Nil when unknown.
    public let surface: FormID?
    /// How loud the hit plays, 0 to 1.
    public let gain: Float

    public init(
        body: ReferenceKey, position: SIMD3<Float>, speedLoss: Float, material: FormID?,
        surface: FormID? = nil, gain: Float = 1
    ) {
        self.body = body
        self.position = position
        self.speedLoss = speedLoss
        self.material = material
        self.surface = surface
        self.gain = gain
    }
}
