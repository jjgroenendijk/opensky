// Draws the menu scene inside the scene pass, after the world layers, with its own
// camera and without depth. See docs/rendering/menu-scene.md.

@preconcurrency import Metal
import OpenSkyFormatsCore
import OpenSkyFormatsMesh
import OpenSkyRenderResources
import OpenSkyShaderTypes
import simd

extension Renderer {
    /// The open menu's scene for this frame; nil stops it. New buffers and textures
    /// join the residency set, and all of them retire when the scene goes away.
    public func setMenuScene(_ scene: MenuScene?) {
        let menu = effects.menuScene
        menu.scene = scene
        guard let scene else {
            retireAllocations(Array(menu.resident.values))
            menu.resident = [:]
            return
        }
        var added: [MTLAllocation] = []
        let uniforms: [MTLAllocation?] = [menu.uniformBuffer]
        let lists = [uniforms] + scene.draws.map { draw -> [MTLAllocation?] in
            [draw.mesh.vertexBuffer, draw.mesh.indexBuffer, draw.texture, draw.palette]
        }
        for allocations in lists {
            for case let allocation? in allocations
                where menu.resident[ObjectIdentifier(allocation)] == nil
            {
                menu.resident[ObjectIdentifier(allocation)] = allocation
                added.append(allocation)
            }
        }
        guard !added.isEmpty else { return }
        residencySet.addAllocations(added)
        residencySet.commit()
    }

    func encodeMenuScene(descriptor: MTL4RenderPassDescriptor, state: inout ScenePassState) {
        let menu = effects.menuScene
        menu.lastDraws = 0
        guard let scene = menu.scene, !scene.draws.isEmpty else { return }
        let viewProjection = scene.viewProjection(aspectRatio: drawableAspectRatio)
        let encoder = state.encoder
        let target = descriptor.colorAttachments[0].texture
        let slice = scene.frontDepthSlice.flatMap { slice in target.map { (slice, $0) } }
        if let (depth, target) = slice {
            encoder.setViewport(MTLViewport(
                originX: 0, originY: 0, width: Double(target.width), height: Double(target.height),
                znear: 0, zfar: Double(depth)
            ))
        }
        encoder.setDepthStencilState(slice == nil ? menu.depthState : menu.frontDepthState)
        encoder.setCullMode(.none)
        let stride = MenuSceneResources.uniformStride
        let base = state.slot * MenuSceneResources.drawLimit * stride
        let draws = scene.draws.prefix(MenuSceneResources.drawLimit)
        for (index, draw) in draws.enumerated() {
            var uniforms = Self.menuSceneUniforms(
                draw, viewProjection: viewProjection, eye: scene.eye
            )
            let offset = base + index * stride
            menu.uniformBuffer.contents().advanced(by: offset)
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<MenuSceneUniforms>.size)
            let mode = draw.material.blend.map(ParticleBlendMode.init(blend:)) ?? .alpha
            encoder.setRenderPipelineState(menu.pipelines.pipeline(for: mode))
            argumentTable.setAddress(
                draw.mesh.vertexBuffer.gpuAddress, index: BufferIndex.menuSceneVertices.rawValue
            )
            argumentTable.setAddress(
                menu.uniformBuffer.gpuAddress + UInt64(offset),
                index: BufferIndex.menuSceneUniforms.rawValue
            )
            let texture = draw.texture ?? swf.whiteTexture
            argumentTable.setTexture(streamedBinding(texture), index: TextureIndex.diffuse.rawValue)
            argumentTable.setTexture(
                streamedBinding(draw.palette ?? texture), index: TextureIndex.effectPalette.rawValue
            )
            encoder.drawIndexedPrimitives(
                primitiveType: .triangle,
                indexCount: draw.mesh.indexCount,
                indexType: .uint16,
                indexBuffer: draw.mesh.indexBuffer.gpuAddress,
                indexBufferLength: draw.mesh.indexBuffer.length
            )
        }
        menu.lastDraws = draws.count
        encoder.setDepthStencilState(depthState)
        if let (_, target) = slice {
            encoder.setViewport(MTLViewport(
                originX: 0, originY: 0, width: Double(target.width), height: Double(target.height),
                znear: 0, zfar: 1
            ))
        }
    }

    static func menuSceneUniforms(
        _ draw: MenuSceneDraw, viewProjection: float4x4, eye: SIMD3<Float>
    ) -> MenuSceneUniforms {
        let material = draw.material
        let shading = material.shading
        return MenuSceneUniforms(
            modelViewProjection: viewProjection * draw.transform,
            model: draw.transform,
            cameraPosition: SIMD4(eye, material.alphaTest ?? 0),
            uvTransform: SIMD4(lowHalf: material.uvOffset, highHalf: material.uvScale),
            effectBaseColor: shading.baseColor,
            effectFalloff: shading.falloff ?? .zero,
            effectBaseColorScale: shading.baseColorScale,
            effectFlags: RenderEffectMaterial.flags(shading, hasPalette: draw.palette != nil),
            hasTexture: draw.texture == nil ? 0 : 1,
            isOpaque: material.blend == nil ? 1 : 0
        )
    }
}
