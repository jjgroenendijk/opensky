// Screen-space UI pass (M8.1.1): resolves the UI scene to a pixel-space draw
// list, uploads any newly-packed glyphs to the r8 atlas, applies a hard
// per-frame quad budget, and records it as the final draws of the scene pass
// (depth-test-always, writes off, premultiplied-over blend, single draw call).
// Setup factory + encode live together, following RendererGrassPass precedent.

import Metal
import MetalKit
import simd

/// The UI pass's long-lived objects, built together at init: GPU pipeline +
/// state + rings + atlas texture, plus the CPU shelf-packed glyph atlas that
/// backs the texture.
nonisolated struct UIResources {
    let pipeline: MTLRenderPipelineState
    let depthState: MTLDepthStencilState
    let sampler: MTLSamplerState
    let atlasTexture: MTLTexture
    let vertexBuffer: MTLBuffer
    let uniformBuffer: MTLBuffer
    let glyphAtlas: UIGlyphAtlas
}

extension Renderer {
    /// Hard per-frame quad cap: overflow is dropped + counted (house style).
    static let uiQuadBudget = 4096
    /// 256-byte-aligned per-frame UIFrameUniforms slot.
    static let alignedUIUniformsSize = (MemoryLayout<UIFrameUniforms>.size + 0xFF) & -0x100

    static func makeUIResources(device: MTLDevice, view: MTKView) throws -> UIResources {
        let atlas = UIGlyphAtlas()
        let vertexCapacity = uiQuadBudget * UIDrawList.verticesPerQuad * maxFramesInFlight
        let vertexBuffer = try makeUniformBuffer(
            device: device,
            length: vertexCapacity * MemoryLayout<UIVertex>.stride,
            label: "UIVertices"
        )
        let uniformBuffer = try makeUniformBuffer(
            device: device,
            length: alignedUIUniformsSize * maxFramesInFlight,
            label: "UIFrameUniforms"
        )
        return try UIResources(
            pipeline: makeUIPipeline(device: device, view: view),
            depthState: makeUIDepthState(device: device),
            sampler: makeUISampler(device: device),
            atlasTexture: makeUIAtlasTexture(device: device, atlas: atlas),
            vertexBuffer: vertexBuffer,
            uniformBuffer: uniformBuffer,
            glyphAtlas: atlas
        )
    }

    private static func makeUIPipeline(
        device: MTLDevice,
        view: MTKView
    ) throws -> MTLRenderPipelineState {
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.defaultLibraryMissing
        }
        let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "uiVertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "uiFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "ScreenSpaceUI"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        guard let color = descriptor.colorAttachments[0] else {
            throw RendererError.pipelineAttachmentMissing
        }
        // Fragment output is premultiplied -> source factor one, over blend.
        color.pixelFormat = view.colorPixelFormat
        color.blendingState = .enabled
        color.sourceRGBBlendFactor = .one
        color.destinationRGBBlendFactor = .oneMinusSourceAlpha
        color.rgbBlendOperation = .add
        color.sourceAlphaBlendFactor = .one
        color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        color.alphaBlendOperation = .add
        return try compiler.makeRenderPipelineState(descriptor: descriptor)
    }

    /// UI draws over everything: compare-always, no depth write.
    private static func makeUIDepthState(device: MTLDevice) throws -> MTLDepthStencilState {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.label = "UIAlwaysNoWrite"
        descriptor.depthCompareFunction = .always
        descriptor.isDepthWriteEnabled = false
        guard let state = device.makeDepthStencilState(descriptor: descriptor) else {
            throw RendererError.depthStateAllocationFailed
        }
        return state
    }

    /// Linear clamp-to-edge sampler for the coverage atlas.
    private static func makeUISampler(device: MTLDevice) throws -> MTLSamplerState {
        let descriptor = MTLSamplerDescriptor()
        descriptor.label = "UIAtlas"
        descriptor.minFilter = .linear
        descriptor.magFilter = .linear
        descriptor.sAddressMode = .clampToEdge
        descriptor.tAddressMode = .clampToEdge
        descriptor.supportArgumentBuffers = true
        guard let sampler = device.makeSamplerState(descriptor: descriptor) else {
            throw RendererError.samplerAllocationFailed
        }
        return sampler
    }

    /// r8Unorm coverage atlas, shared storage (CPU uploads packed glyphs).
    private static func makeUIAtlasTexture(
        device: MTLDevice,
        atlas: UIGlyphAtlas
    ) throws -> MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .r8Unorm,
            width: atlas.width,
            height: atlas.height,
            mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        texture.label = "UIGlyphAtlas"
        atlas.pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, atlas.width, atlas.height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: atlas.width
            )
        }
        return texture
    }

    /// Uploads the atlas only when new glyphs packed since the last upload. The
    /// atlas is a single shared texture; the glyph set stabilizes after a
    /// scene's first frame, so steady-state frames skip this entirely and no
    /// in-flight frame races a re-upload of identical bytes.
    private func uploadUIAtlasIfNeeded() {
        let atlas = uiResources.glyphAtlas
        guard atlas.revision != uiUploadedAtlasRevision else { return }
        atlas.pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            uiResources.atlasTexture.replace(
                region: MTLRegionMake2D(0, 0, atlas.width, atlas.height),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: atlas.width
            )
        }
        uiUploadedAtlasRevision = atlas.revision
    }

    /// Encodes the UI overlay as the final draws of the scene pass. Viewport
    /// pixel size comes from the pass's color attachment (drawable or offscreen
    /// target), so both render paths get the overlay automatically.
    func encodeUI(descriptor: MTL4RenderPassDescriptor, state: inout ScenePassState) {
        let atlas = uiResources.glyphAtlas
        let colorTexture = descriptor.colorAttachments[0].texture
        let viewportPixels = SIMD2<Float>(
            Float(colorTexture?.width ?? 0), Float(colorTexture?.height ?? 0)
        )
        var stats = UIDrawStats(atlasWidth: atlas.width, atlasHeight: atlas.height)
        guard uiEnabled, viewportPixels.x > 0, viewportPixels.y > 0 else {
            lastUIDrawStats = stats
            return
        }
        let list = uiScene.resolve(viewportPixels: viewportPixels, scale: uiScale, atlas: atlas)
        uploadUIAtlasIfNeeded()
        let budgeted = list.budgeted(maxQuads: Self.uiQuadBudget)
        stats.quads = budgeted.quads
        stats.glyphs = list.glyphCount
        stats.dropped = budgeted.dropped
        guard budgeted.quads > 0 else {
            lastUIDrawStats = stats
            return
        }
        bindAndDrawUI(budgeted: budgeted, viewportPixels: viewportPixels, state: &state)
        stats.drawCalls = 1
        lastUIDrawStats = stats
    }

    private func bindAndDrawUI(
        budgeted: UIBudgetResult,
        viewportPixels: SIMD2<Float>,
        state: inout ScenePassState
    ) {
        let vertexOffset = writeUIVertices(budgeted.vertices, slot: state.slot)
        let uniformOffset = writeUIUniforms(viewportPixels: viewportPixels, slot: state.slot)
        let encoder = state.encoder
        encoder.setRenderPipelineState(uiResources.pipeline)
        encoder.setDepthStencilState(uiResources.depthState)
        encoder.setCullMode(.none)
        argumentTable.setAddress(
            uiResources.vertexBuffer.gpuAddress + UInt64(vertexOffset),
            index: BufferIndex.uiVertices.rawValue
        )
        argumentTable.setAddress(
            uiResources.uniformBuffer.gpuAddress + UInt64(uniformOffset),
            index: BufferIndex.uiUniforms.rawValue
        )
        argumentTable.setTexture(
            uiResources.atlasTexture.gpuResourceID, index: TextureIndex.uiAtlas.rawValue
        )
        argumentTable.setSamplerState(
            uiResources.sampler.gpuResourceID, index: SamplerIndex.uiAtlas.rawValue
        )
        encoder.drawPrimitives(
            primitiveType: .triangle,
            vertexStart: 0,
            vertexCount: budgeted.quads * UIDrawList.verticesPerQuad
        )
    }

    /// Copies this frame's vertices into the ring slot; returns the byte offset.
    private func writeUIVertices(_ vertices: [UIVertex], slot: Int) -> Int {
        let stride = MemoryLayout<UIVertex>.stride
        let capacity = Self.uiQuadBudget * UIDrawList.verticesPerQuad
        let offset = slot * capacity * stride
        vertices.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            uiResources.vertexBuffer.contents().advanced(by: offset).copyMemory(
                from: base, byteCount: bytes.count
            )
        }
        return offset
    }

    private func writeUIUniforms(viewportPixels: SIMD2<Float>, slot: Int) -> Int {
        let offset = Self.alignedUIUniformsSize * slot
        var uniforms = UIFrameUniforms(viewportSize: viewportPixels)
        uiResources.uniformBuffer.contents().advanced(by: offset)
            .copyMemory(from: &uniforms, byteCount: MemoryLayout<UIFrameUniforms>.size)
        return offset
    }
}
