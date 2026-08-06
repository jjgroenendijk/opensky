// Swept movement helpers split from CapsuleCollision.swift for file limits.

import simd

nonisolated extension CapsuleWorldCollider {
    func capsuleBounds(at feet: SIMD3<Float>) -> ModelBounds {
        let radius = SIMD3<Float>(repeating: capsule.radius)
        return ModelBounds(
            min: feet + SIMD3<Float>(0, 0, capsule.radius) - radius,
            max: feet + SIMD3<Float>(0, 0, capsule.height - capsule.radius) + radius
        )
    }
}
