// Drawing a reference physics is moving. The baked instance matrix stays, and the
// rigid delta from built to live pose is applied at instance upload, so no cell
// rebuilds and the draw group never changes. The skinned player body rebuilds its
// groups instead. See docs/engine/dynamic-body-drawing.md.

import OpenSkyFormatsCore
import simd

nonisolated extension DrawInstance {
    /// This instance carried through a rigid transform: matrices recomposed and
    /// the culling AABB moved with them, so a body that has left its baked
    /// bounds is still drawn.
    public func moved(by delta: float4x4) -> DrawInstance {
        let matrix = delta * modelMatrix
        return DrawInstance(
            modelMatrix: matrix,
            normalMatrix: MatrixMath.normalMatrix(matrix),
            bounds: bounds?.transformed(by: delta),
            castsShadows: castsShadows,
            receivesPointLights: receivesPointLights,
            receivesShadows: receivesShadows,
            referenceFormID: referenceFormID,
            layer: layer,
            owner: owner
        )
    }
}

extension Renderer {
    /// The instance as this frame draws it: baked, or moved when a body owns it. An
    /// identity check skips the map lookup, and a body at rest is absent from the map.
    public func drawn(_ instance: DrawInstance) -> DrawInstance {
        guard
            instance.referenceFormID != 0, !instanceDeltas.isEmpty,
            let delta = instanceDeltas[instance.referenceFormID]
        else { return instance }
        return instance.moved(by: delta)
    }

    /// A vehicle follower wins over a walking pose, because a rider does not walk. A
    /// scripted move wins over both, because a script placed it on purpose.
    func mergeInstanceDeltas() {
        let input = frameInput.instancePoses
        var moving = input.npcDeltas.isEmpty
            ? input.dynamicDeltas
            : input.dynamicDeltas.merging(input.npcDeltas) { _, npc in npc }
        for poses in [input.vehiclePoses, input.scriptedPoses] where !poses.isEmpty {
            moving.merge(deltas(from: poses)) { _, posed in posed }
        }
        instanceDeltas = moving
    }

    /// A rebuilt cell bakes a newer placement, so the delta follows the current scene.
    private func deltas(from poses: [UInt32: float4x4]) -> [UInt32: float4x4] {
        poses.reduce(into: [:]) { deltas, entry in
            guard let built = scene.referencePlacements[entry.key] else { return }
            deltas[entry.key] = entry.value * Self.rigid(built).inverse
        }
    }

    /// The placement without its scale, so the delta keeps the built scale.
    private static func rigid(_ matrix: float4x4) -> float4x4 {
        func unit(_ column: SIMD4<Float>) -> SIMD4<Float> {
            SIMD4(simd_normalize(SIMD3(column.x, column.y, column.z)), 0)
        }
        return float4x4(
            unit(matrix.columns.0), unit(matrix.columns.1), unit(matrix.columns.2),
            matrix.columns.3
        )
    }
}
