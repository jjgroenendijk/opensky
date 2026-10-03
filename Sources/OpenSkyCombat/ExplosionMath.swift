// The pure parts of an explosion: damage falloff over the radius, the strength
// an image-space modifier plays at, and seeded weighted debris. See
// docs/formats/explosions.md, section "Runtime".

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

nonisolated public enum ExplosionFalloff {
    /// Full damage at the center, falling linearly to zero at the edge. A zero radius
    /// reaches only the center point.
    public static func damage(_ base: Float, radius: Float, distance: Float) -> Float {
        guard base.isFinite, base > 0, distance.isFinite else { return 0 }
        guard radius.isFinite, radius > 0 else { return distance <= 0 ? base : 0 }
        let fraction = max(distance, 0) / radius
        return fraction >= 1 ? 0 : base * (1 - fraction)
    }

    /// Modifier strength for a viewer `distance` away: 1 at the center, 0 at the
    /// image-space radius. A zero radius plays at full strength, as for a spell hit.
    public static func imageSpaceStrength(radius: Float, distance: Float) -> Float {
        guard radius.isFinite, radius > 0 else { return 1 }
        guard distance.isFinite else { return 0 }
        return min(max(1 - max(distance, 0) / radius, 0), 1)
    }
}

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
}

nonisolated public enum DebrisSelection {
    /// Seconds a piece stays before it is removed.
    public static let lifetime: Float = 6
    /// Units per second squared, roughly 9.8 m/s² at 70 units per meter.
    public static let gravity: Float = 686
    /// Pieces one detonation throws.
    public static let pieceCount = 6
    /// The launch force of a sidebar throw: a mid-size explosion's.
    public static let panelForce: Float = 400

    /// `count` models drawn by their DEBR percentage, with replacement. The same seed
    /// draws the same models in the same order. A zero total weight draws evenly.
    public static func pick(_ models: [Debris.Model], count: Int, seed: UInt64) -> [Debris.Model] {
        guard !models.isEmpty, count > 0 else { return [] }
        var random = SplitMix64(seed: seed)
        let weights = models.map { Double($0.percentage) }
        let total = weights.reduce(0, +)
        return (0 ..< count).map { _ in
            let roll = Double(random.next() >> 11) / Double(1 << 53)
            guard total > 0 else { return models[Int(roll * Double(models.count)) % models.count] }
            var remaining = roll * total
            for (model, weight) in zip(models, weights) {
                remaining -= weight
                if remaining < 0 {
                    return model
                }
            }
            return models[models.count - 1]
        }
    }

    /// Throws the picked models outward and up from `center`, faster for a larger force.
    public static func launch(
        _ models: [Debris.Model],
        from center: SIMD3<Float>,
        force: Float,
        seed: UInt64
    ) -> [DebrisPiece] {
        var random = SplitMix64(seed: seed ^ 0xD3B5)
        let speed = 300 + min(max(force.isFinite ? force : 0, 0), 2000) * 0.25
        return pick(models, count: pieceCount, seed: seed).enumerated().map { index, model in
            let angle = 2 * Float.pi * (Float(index) + unit(&random)) / Float(pieceCount)
            let lift = 0.5 + 0.5 * unit(&random)
            let direction = simd_normalize(SIMD3(cos(angle), sin(angle), lift))
            let axis = simd_normalize(SIMD3(unit(&random), unit(&random), 1) - 0.5)
            return DebrisPiece(
                path: model.path,
                position: center,
                velocity: direction * speed,
                spin: axis * (2 + 6 * unit(&random)),
                lifetime: lifetime
            )
        }
    }

    /// Moves every piece one step under gravity and drops the expired.
    public static func step(_ pieces: [DebrisPiece], seconds: Float) -> [DebrisPiece] {
        let dt = seconds.isFinite ? max(seconds, 0) : 0
        return pieces.compactMap { piece in
            var piece = piece
            piece.age += dt
            piece.velocity.z -= gravity * dt
            piece.position += piece.velocity * dt
            return piece.isExpired ? nil : piece
        }
    }

    private static func unit(_ random: inout SplitMix64) -> Float {
        Float(random.next() >> 40) / Float(1 << 24)
    }
}
