// Per-frame GPU ring sizing, split from Renderer.swift (file-length limits,
// RendererSetup.swift precedent). Pure allocation policy: how many aligned
// slots a scene needs and how to allocate every ring for it. The regrow +
// retire machinery that consumes these lives in Renderer.swift's scene-swap
// extension (it needs the renderer's private state).

import Metal
import simd

extension Renderer {
    /// Ring slots per frame for `count` draws: next power of two, min 1 —
    /// headroom so the per-cell-crossing swaps of streaming rarely realloc.
    static func slotCapacity(for count: Int) -> Int {
        count <= 1 ? 1 : 1 << (Int.bitWidth - (count - 1).leadingZeroBitCount)
    }

    /// Shadow draw-ring slots one frame can need for a `drawCapacity`-slot
    /// scene: one ShadowDrawUniforms per cascade per drawn caster.
    static func shadowDrawCapacity(_ drawCapacity: Int) -> Int {
        ShadowConstant.cascadeCount.rawValue * drawCapacity
    }

    /// Every per-frame ring a scene needs: the scene-pass draw + point-light +
    /// instance rings, plus the parallel shadow-pass draw + instance rings.
    struct SceneRings {
        let drawBuffer: MTLBuffer
        let pointLightBuffer: MTLBuffer
        let drawCapacity: Int
        let instanceBuffer: MTLBuffer
        let instanceCapacity: Int
        let shadowDrawBuffer: MTLBuffer
        let shadowInstanceBuffer: MTLBuffer
    }

    /// Allocates every per-frame ring for a scene — shared by init and the
    /// regrow path in setScene (identical sizing policy in one place).
    static func makeSceneRings(device: MTLDevice, scene: RenderScene) throws -> SceneRings {
        let drawCapacity = slotCapacity(for: scene.drawCount)
        let instanceCapacity = slotCapacity(for: scene.instanceCount)
        let instanceLength = MemoryLayout<InstanceTransform>.stride
            * instanceCapacity * maxFramesInFlight
        return try SceneRings(
            drawBuffer: makeUniformBuffer(
                device: device,
                length: alignedDrawUniformsSize * drawCapacity * maxFramesInFlight,
                label: "DrawUniforms"
            ),
            pointLightBuffer: makeUniformBuffer(
                device: device,
                length: MemoryLayout<PointLightUniform>.stride
                    * LightingConstant.maxPointLights.rawValue
                    * drawCapacity * maxFramesInFlight,
                label: "PointLights"
            ),
            drawCapacity: drawCapacity,
            instanceBuffer: makeUniformBuffer(
                device: device, length: instanceLength, label: "InstanceTransforms"
            ),
            instanceCapacity: instanceCapacity,
            shadowDrawBuffer: makeUniformBuffer(
                device: device,
                length: alignedDrawUniformsSize
                    * shadowDrawCapacity(drawCapacity) * maxFramesInFlight,
                label: "ShadowDrawUniforms"
            ),
            // Per-cascade caster culling (M7.1.2) writes a contiguous
            // instance run per cascade, so worst case is every instance drawn
            // in every cascade -> cascadeCount x the scene instance ring.
            shadowInstanceBuffer: makeUniformBuffer(
                device: device,
                length: instanceLength * ShadowConstant.cascadeCount.rawValue,
                label: "ShadowInstanceTransforms"
            )
        )
    }
}
