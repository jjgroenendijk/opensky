// A living actor's ragdoll: the push of a knockdown, the test that it lies still enough to
// get up, and the pose it gets up from (docs/engine/ragdoll.md#knockdown).

import OpenSkyFormatsMesh
import simd

nonisolated extension RagdollInstance {
    /// The get-up test: the faster of the two key bodies moves slower than 0.025 m²/s² in
    /// Havok units, about 11 units a second.
    static let getUpSpeedSquared: Float = 0.025 * NIFCollisionModel.havokToEngineScale
        * NIFCollisionModel.havokToEngineScale

    /// The squared speed of the faster of the first two bodies, the pelvis and the spine
    /// on a person.
    var keyBodySpeedSquared: Float {
        bodies.prefix(2).map { simd_length_squared($0.linearVelocity) }.max() ?? 0
    }

    public var isStillEnoughToGetUp: Bool {
        keyBodySpeedSquared < Self.getUpSpeedSquared
    }

    /// Adds `speed` units a second to every body, away from `source`, times the weight
    /// `weight` gives the body's bone.
    public mutating func push(
        awayFrom source: SIMD3<Float>, speed: Float, weight: (String) -> Float
    ) {
        guard speed.isFinite, speed != 0 else { return }
        wake()
        for (index, bone) in definition.bones.enumerated() where bodies.indices.contains(index) {
            let offset = bodies[index].position - source
            let length = simd_length(offset)
            let direction = length > 0.001 ? offset / length : SIMD3<Float>(0, 0, 1)
            bodies[index].linearVelocity += direction * speed * weight(bone.boneName)
        }
    }

    /// The world position of the body on `boneName`.
    public func position(ofBone boneName: String) -> SIMD3<Float>? {
        definition.bones.firstIndex { $0.boneName == boneName }
            .flatMap { bodies.indices.contains($0) ? bodies[$0].originPosition : nil }
    }

    /// The lowest body origin: about the ground under a body that lies on it.
    public var lowestBodyHeight: Float? {
        bodies.map(\.originPosition.z).min()
    }
}
