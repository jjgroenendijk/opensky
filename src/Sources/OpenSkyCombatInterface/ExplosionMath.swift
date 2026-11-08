import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
public import simd

/// One thrown debris model, flying ballistically until its time runs out.
nonisolated public struct DebrisPiece: Equatable, Sendable {
    public let path: String
    public var position: SIMD3<Float>
    public var velocity: SIMD3<Float>
    /// Rotation axis times radians per second.
    public let spin: SIMD3<Float>
    public var age: Float = 0
    public let lifetime: Float

    public var isExpired: Bool {
        age >= lifetime
    }

    /// The model matrix at the current age: spun about its axis, then placed.
    public var transform: float4x4 {
        let rate = simd_length(spin)
        var matrix = matrix_identity_float4x4
        if rate > 0 {
            matrix = float4x4(simd_quatf(angle: rate * age, axis: spin / rate))
        }
        matrix.columns.3 = SIMD4(position, 1)
        return matrix
    }

    public init(
        path: String,
        position: SIMD3<Float>,
        velocity: SIMD3<Float>,
        spin: SIMD3<Float>,
        age: Float = 0,
        lifetime: Float
    ) {
        self.path = path
        self.position = position
        self.velocity = velocity
        self.spin = spin
        self.age = age
        self.lifetime = lifetime
    }
}
