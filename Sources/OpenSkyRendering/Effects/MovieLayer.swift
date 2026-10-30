// A movie picture over the whole frame, letterboxed on black, after the SWF menus and
// before the dev UI. The planes upload into one texture set per frame slot, so an upload
// never touches a picture the GPU still reads. See docs/engine/movies.md.

import Metal
import MetalKit
import OpenSkyFormatsCore
import OpenSkyRenderResources
import OpenSkyShaderTypes

/// The three plane textures of one picture size.
struct MoviePlaneTextures {
    let luma: MTLTexture
    let chromaBlue: MTLTexture
    let chromaRed: MTLTexture
    /// The serial of the picture these textures hold.
    var serial = 0

    var allocations: [MTLAllocation] {
        [luma, chromaBlue, chromaRed]
    }

    func fits(_ picture: MoviePicture) -> Bool {
        luma.width == picture.width && luma.height == picture.height
    }
}

public final class MovieLayer {
    nonisolated static let verticesPerQuad = 6

    let pipeline: MTLRenderPipelineState
    let vertexBuffer: MTLBuffer
    /// The picture to show; nil draws nothing.
    public internal(set) var picture: MoviePicture?
    /// False stretches the picture over the whole frame.
    var letterbox = true
    var pictureSerial = 0
    var slots: [MoviePlaneTextures?] = Array(repeating: nil, count: GPUFactory.maxFramesInFlight)

    init(device: MTLDevice, library: MTLLibrary, view: MTKView, compiler: PipelineCache) throws {
        let vertexFunction = MTL4LibraryFunctionDescriptor()
        vertexFunction.library = library
        vertexFunction.name = "movieVertex"
        let fragmentFunction = MTL4LibraryFunctionDescriptor()
        fragmentFunction.library = library
        fragmentFunction.name = "movieFragment"
        let descriptor = MTL4RenderPipelineDescriptor()
        descriptor.label = "Movie"
        descriptor.rasterSampleCount = view.sampleCount
        descriptor.vertexFunctionDescriptor = vertexFunction
        descriptor.fragmentFunctionDescriptor = fragmentFunction
        guard let color = descriptor.colorAttachments[0] else {
            throw RendererError.pipelineAttachmentMissing
        }
        color.pixelFormat = view.colorPixelFormat
        pipeline = try compiler.makeRenderPipelineState(descriptor: descriptor)
        let length = Self.verticesPerQuad * MemoryLayout<UIVertex>.stride
            * GPUFactory.maxFramesInFlight
        guard let buffer = device.makeBuffer(length: length, options: .storageModeShared) else {
            throw RendererError.bufferAllocationFailed
        }
        buffer.label = "MovieVertices"
        vertexBuffer = buffer
    }

    /// One quad over the whole target. Outside the letterboxed picture the uv leaves 0 to 1.
    nonisolated static func vertices(
        picture: SIMD2<Float>, target: SIMD2<Float>, fullRange: Bool, letterbox: Bool = true
    ) -> [UIVertex] {
        let fit = min(target.x / picture.x, target.y / picture.y)
        let shown = letterbox ? picture * fit / target : SIMD2<Float>(repeating: 1)
        let reach = 1 / max(shown, SIMD2(repeating: 1e-6))
        let low = 0.5 - reach / 2
        let high = 0.5 + reach / 2
        let colour = SIMD4<Float>(fullRange ? 1 : 0, 0, 0, 1)
        func corner(_ x: Float, _ y: Float, _ u: Float, _ v: Float) -> UIVertex {
            UIVertex(position: SIMD2(x, y), uv: SIMD2(u, v), color: colour)
        }
        let topLeft = corner(-1, 1, low.x, low.y)
        let topRight = corner(1, 1, high.x, low.y)
        let bottomLeft = corner(-1, -1, low.x, high.y)
        let bottomRight = corner(1, -1, high.x, high.y)
        return [topLeft, bottomLeft, bottomRight, topLeft, bottomRight, topRight]
    }

    static func makePlanes(device: MTLDevice, picture: MoviePicture) throws -> MoviePlaneTextures {
        func plane(_ width: Int, _ height: Int, _ label: String) throws -> MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .r8Unorm, width: width, height: height, mipmapped: false
            )
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw RendererError.textureAllocationFailed
            }
            texture.label = label
            return texture
        }
        return try MoviePlaneTextures(
            luma: plane(picture.width, picture.height, "MovieLuma"),
            chromaBlue: plane(picture.chromaWidth, picture.chromaHeight, "MovieChromaBlue"),
            chromaRed: plane(picture.chromaWidth, picture.chromaHeight, "MovieChromaRed")
        )
    }
}

extension Renderer {
    /// Shows `picture` over everything but the dev UI, or nothing for nil.
    public func setMoviePicture(_ picture: MoviePicture?, letterbox: Bool = true) {
        let layer = effects.movie
        guard let picture, picture.hasValidPlanes else {
            layer.picture = nil
            retireAllocations(layer.slots.compactMap(\.self).flatMap(\.allocations))
            layer.slots = Array(repeating: nil, count: layer.slots.count)
            return
        }
        layer.picture = picture
        layer.letterbox = letterbox
        layer.pictureSerial += 1
    }

    func encodeMovie(descriptor: MTL4RenderPassDescriptor, state: inout ScenePassState) {
        let layer = effects.movie
        guard
            let picture = layer.picture,
            let target = descriptor.colorAttachments[0].texture, target.height > 0,
            let planes = moviePlanes(for: picture, slot: state.slot)
        else { return }
        let vertices = MovieLayer.vertices(
            picture: SIMD2(Float(picture.width), Float(picture.height)),
            target: SIMD2(Float(target.width), Float(target.height)),
            fullRange: picture.isFullRange, letterbox: layer.letterbox
        )
        let offset = state.slot * MovieLayer.verticesPerQuad * MemoryLayout<UIVertex>.stride
        vertices.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            layer.vertexBuffer.contents().advanced(by: offset)
                .copyMemory(from: base, byteCount: bytes.count)
        }
        let encoder = state.encoder
        encoder.setRenderPipelineState(layer.pipeline)
        encoder.setDepthStencilState(uiResources.depthState)
        encoder.setCullMode(.none)
        argumentTable.setSamplerState(sampler.gpuResourceID, index: SamplerIndex.trilinear.rawValue)
        argumentTable.setAddress(
            layer.vertexBuffer.gpuAddress + UInt64(offset), index: BufferIndex.uiVertices.rawValue
        )
        argumentTable.setTexture(planes.luma.gpuResourceID, index: TextureIndex.movieLuma.rawValue)
        argumentTable.setTexture(
            planes.chromaBlue.gpuResourceID, index: TextureIndex.movieChromaBlue.rawValue
        )
        argumentTable.setTexture(
            planes.chromaRed.gpuResourceID, index: TextureIndex.movieChromaRed.rawValue
        )
        encoder.drawPrimitives(
            primitiveType: .triangle, vertexStart: 0, vertexCount: MovieLayer.verticesPerQuad
        )
        state.stats.drawCalls += 1
    }

    /// The slot's textures, holding the current picture. Nil when a texture fails to allocate.
    private func moviePlanes(for picture: MoviePicture, slot: Int) -> MoviePlaneTextures? {
        let layer = effects.movie
        var planes = layer.slots[slot]
        if planes?.fits(picture) != true {
            guard let made = try? MovieLayer.makePlanes(device: device, picture: picture) else {
                return nil
            }
            retireAllocations(planes?.allocations ?? [])
            residencySet.addAllocations(made.allocations)
            residencySet.commit()
            planes = made
        }
        guard var current = planes else { return nil }
        if current.serial != layer.pictureSerial {
            upload(picture.luma, to: current.luma)
            upload(picture.chromaBlue, to: current.chromaBlue)
            upload(picture.chromaRed, to: current.chromaRed)
            current.serial = layer.pictureSerial
        }
        layer.slots[slot] = current
        return current
    }

    private func upload(_ bytes: Data, to texture: MTLTexture) {
        bytes.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, texture.width, texture.height),
                mipmapLevel: 0, withBytes: base, bytesPerRow: texture.width
            )
        }
    }
}
