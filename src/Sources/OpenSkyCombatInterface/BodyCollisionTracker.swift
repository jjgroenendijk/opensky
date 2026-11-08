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

    public init(
        body: ReferenceKey, position: SIMD3<Float>, speedLoss: Float, material: FormID?,
        surface: FormID? = nil
    ) {
        self.body = body
        self.position = position
        self.speedLoss = speedLoss
        self.material = material
        self.surface = surface
    }
}
