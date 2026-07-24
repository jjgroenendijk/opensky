// SWF display-list encode (M8.2.4): renders the assigned movie's frame-1
// command stream over the finished 3D frame, inside the scene pass after the
// world draws and before the dev UI overlay. Per draw: one 256-byte uniform
// slot carrying the concatenated place -> movie -> viewport -> NDC transform,
// the fill mapping, and the CXFORM; shape draws bind the movie's static
// twip-space vertex buffer, text draws bind the per-frame glyph-quad ring.
// Clip layers use a counting stencil: begin/end mask draws increment/
// decrement, content tests stencil == active-clip count.

import Metal
import MetalKit
import simd

extension Renderer {
    /// SWF layer A/B toggle. Off -> the layer encodes nothing and the frame
    /// matches a no-movie baseline exactly.
    var swfEnabled: Bool {
        get { swf.enabled }
        set { swf.enabled = newValue }
    }

    /// The movie package assigned via `setSWFMovie`; nil -> no SWF draws.
    var swfScene: SWFMovieScene? {
        swf.movie?.scene
    }

    /// SWF draw accounting from the most recently encoded frame.
    var lastSWFDrawStats: SWFDrawStats {
        swf.lastDrawStats
    }

    /// Assigns (or clears) the movie the SWF layer renders. Builds the GPU
    /// package synchronously; the old package's allocations retire once
    /// in-flight frames drain. Main thread, between frames, like `setScene`.
    func setSWFMovie(_ scene: SWFMovieScene?) throws {
        purgeRetiredResources()
        let old = swf.movie
        if let scene {
            swf.generation += 1
            let resources = try SWFMovieResources(
                device: device, scene: scene, generation: swf.generation
            )
            swf.movie = resources
            residencySet.addAllocations(resources.residencyAllocations)
            residencySet.commit()
        } else {
            swf.movie = nil
        }
        if let old {
            retireAllocations(old.residencyAllocations)
        }
    }

    /// Encodes the SWF layer into the open scene pass. Deterministic: the
    /// same movie and viewport produce the same command stream, uniforms, and
    /// glyph quads, so repeated frames are byte-identical.
    func encodeSWF(descriptor: MTL4RenderPassDescriptor, state: inout ScenePassState) {
        var stats = SWFDrawStats()
        defer { swf.lastDrawStats = stats }
        guard swf.enabled, let movie = swf.movie else { return }
        let colorTexture = descriptor.colorAttachments[0].texture
        let viewport = SIMD2<Float>(
            Float(colorTexture?.width ?? 0), Float(colorTexture?.height ?? 0)
        )
        guard viewport.x > 0, viewport.y > 0 else { return }
        var frame = SWFFrameBuilder(
            movie: movie,
            viewport: viewport,
            glyphAtlas: uiResources.glyphAtlas
        )
        frame.build()
        stats.skippedItems = frame.skipped + movie.buildSkipped
        uploadUIAtlasIfNeeded()
        guard !frame.ops.isEmpty else { return }
        writeSWFFrameData(frame: frame, movie: movie, slot: state.slot)
        encodeSWFOps(frame: frame, movie: movie, state: &state, stats: &stats)
    }

    private func writeSWFFrameData(frame: SWFFrameBuilder, movie: SWFMovieResources, slot: Int) {
        let uniformStride = Self.alignedSWFUniformsSize
        let uniformBase = slot * max(1, movie.drawCapacity) * uniformStride
        let contents = movie.uniformBuffer.contents()
        for (index, var uniforms) in frame.uniforms.enumerated() {
            contents.advanced(by: uniformBase + index * uniformStride)
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<SWFDrawUniforms>.size)
        }
        let glyphBase = slot * max(1, movie.glyphQuadCapacity) * 6
            * MemoryLayout<SWFVertex>.stride
        frame.glyphVertices.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            movie.glyphVertexBuffer.contents().advanced(by: glyphBase)
                .copyMemory(from: base, byteCount: bytes.count)
        }
    }

    private func encodeSWFOps(
        frame: SWFFrameBuilder,
        movie: SWFMovieResources,
        state: inout ScenePassState,
        stats: inout SWFDrawStats
    ) {
        let encoder = state.encoder
        encoder.setCullMode(.none)
        argumentTable.setTexture(
            (movie.gradientTexture ?? swf.fallbackRamp).gpuResourceID,
            index: TextureIndex.swfGradient.rawValue
        )
        argumentTable.setTexture(
            uiResources.atlasTexture.gpuResourceID, index: TextureIndex.uiAtlas.rawValue
        )
        argumentTable.setSamplerState(
            uiResources.sampler.gpuResourceID, index: SamplerIndex.uiAtlas.rawValue
        )
        argumentTable.setSamplerState(
            swf.repeatSampler.gpuResourceID, index: SamplerIndex.swfRepeat.rawValue
        )
        let uniformStride = Self.alignedSWFUniformsSize
        let uniformBase = state.slot * max(1, movie.drawCapacity) * uniformStride
        let glyphBase = state.slot * max(1, movie.glyphQuadCapacity) * 6
            * MemoryLayout<SWFVertex>.stride
        for op in frame.ops {
            switch op.kind {
            case let .content(clipCount):
                encoder.setRenderPipelineState(swf.contentPipeline)
                encoder.setDepthStencilState(swf.contentDepthState)
                encoder.setStencilReferenceValue(UInt32(clamping: clipCount))
            case .maskIncrement:
                encoder.setRenderPipelineState(swf.maskPipeline)
                encoder.setDepthStencilState(swf.maskIncrementState)
                stats.maskDraws += 1
            case .maskDecrement:
                encoder.setRenderPipelineState(swf.maskPipeline)
                encoder.setDepthStencilState(swf.maskDecrementState)
                stats.maskDraws += 1
            }
            let vertexBuffer = op.usesGlyphBuffer ? movie.glyphVertexBuffer : movie.vertexBuffer
            argumentTable.setAddress(
                vertexBuffer.gpuAddress + UInt64(op.usesGlyphBuffer ? glyphBase : 0),
                index: BufferIndex.swfVertices.rawValue
            )
            argumentTable.setAddress(
                movie.uniformBuffer.gpuAddress
                    + UInt64(uniformBase + op.uniformIndex * uniformStride),
                index: BufferIndex.swfUniforms.rawValue
            )
            let bitmap = op.bitmapId.flatMap { movie.bitmaps[$0]?.texture } ?? swf.whiteTexture
            argumentTable.setTexture(
                bitmap.gpuResourceID, index: TextureIndex.swfBitmap.rawValue
            )
            encoder.drawPrimitives(
                primitiveType: .triangle,
                vertexStart: op.vertexStart,
                vertexCount: op.vertexCount
            )
            stats.drawCalls += 1
            stats.triangles += op.vertexCount / 3
            stats.glyphs += op.glyphCount
        }
    }
}

/// One encoded draw of the SWF layer.
nonisolated struct SWFDrawOp {
    enum Kind {
        case content(clipCount: Int)
        case maskIncrement
        case maskDecrement
    }

    let kind: Kind
    let usesGlyphBuffer: Bool
    let vertexStart: Int
    let vertexCount: Int
    let uniformIndex: Int
    let bitmapId: UInt16?
    let glyphCount: Int
}

/// Per-frame CPU pass: walks the flattened command stream, producing draw ops
/// with their uniforms and the glyph-quad vertices for text draws.
nonisolated struct SWFFrameBuilder {
    let movie: SWFMovieResources
    let glyphAtlas: UIGlyphAtlas
    /// Character-local twips -> framebuffer pixels for the stage.
    private let stageToPixels: SWFTransform
    /// Framebuffer pixels -> NDC.
    private let pixelsToClip: SWFTransform

    private(set) var ops: [SWFDrawOp] = []
    private(set) var uniforms: [SWFDrawUniforms] = []
    private(set) var glyphVertices: [SWFVertex] = []
    private(set) var skipped = 0
    private var glyphQuadCount = 0

    init(movie: SWFMovieResources, viewport: SIMD2<Float>, glyphAtlas: UIGlyphAtlas) {
        self.movie = movie
        self.glyphAtlas = glyphAtlas
        stageToPixels = SWFViewportMapping.twipsToPixels(
            frameSize: movie.scene.movie.frameSize, viewportPixels: viewport
        )
        pixelsToClip = SWFViewportMapping.pixelsToClip(viewportPixels: viewport)
    }

    mutating func build() {
        for (index, command) in movie.commands.enumerated() {
            switch command {
            case let .beginClip(masks):
                appendMasks(masks, kind: .maskIncrement)
            case let .endClip(masks):
                appendMasks(masks, kind: .maskDecrement)
            case let .draw(item, clipCount):
                appendDraw(item: item, clipCount: clipCount, commandIndex: index)
            }
        }
    }

    private mutating func appendMasks(_ masks: [SWFSceneItem], kind: SWFDrawOp.Kind) {
        for mask in masks {
            guard
                case let .shape(id) = mask.content,
                let entry = movie.shapes[id], entry.vertexCount > 0,
                uniforms.count < movie.drawCapacity
            else {
                skipped += 1
                continue
            }
            uniforms.append(makeUniforms(
                transform: clipTransform(for: mask),
                fill: .solid(SIMD4(repeating: 0)),
                colorTransform: .identity
            ))
            ops.append(SWFDrawOp(
                kind: kind,
                usesGlyphBuffer: false,
                vertexStart: entry.vertexStart,
                vertexCount: entry.vertexCount,
                uniformIndex: uniforms.count - 1,
                bitmapId: nil,
                glyphCount: 0
            ))
        }
    }

    private mutating func appendDraw(item: SWFSceneItem, clipCount: Int, commandIndex: Int) {
        switch item.content {
        case let .shape(id):
            appendShapeDraw(item: item, shapeId: id, clipCount: clipCount)
        case .staticText, .editText:
            appendTextDraw(item: item, clipCount: clipCount, commandIndex: commandIndex)
        }
    }

    private mutating func appendShapeDraw(item: SWFSceneItem, shapeId: UInt16, clipCount: Int) {
        guard let entry = movie.shapes[shapeId] else {
            skipped += 1
            return
        }
        let transform = clipTransform(for: item)
        for run in entry.runs {
            guard uniforms.count < movie.drawCapacity else {
                skipped += 1
                continue
            }
            uniforms.append(makeUniforms(
                transform: transform,
                fill: run.fill,
                colorTransform: item.colorTransform
            ))
            let bitmapId: UInt16? = if case let .bitmap(id, _, _) = run.fill {
                id
            } else {
                nil
            }
            ops.append(SWFDrawOp(
                kind: .content(clipCount: clipCount),
                usesGlyphBuffer: false,
                vertexStart: run.vertexStart,
                vertexCount: run.vertexCount,
                uniformIndex: uniforms.count - 1,
                bitmapId: bitmapId,
                glyphCount: 0
            ))
        }
    }

    /// Text draws: glyphs rasterize at the on-screen pixel size and the quads
    /// are laid out in pixel space (axis-aligned — glyph quads follow the
    /// transform's position and scale, not its rotation/skew; vanilla UI text
    /// is unrotated).
    private mutating func appendTextDraw(item: SWFSceneItem, clipCount: Int, commandIndex: Int) {
        guard let runs = movie.textPlans[commandIndex], !runs.isEmpty else { return }
        let textToPixels = stageToPixels.concatenating(item.transform)
        let pixelsPerTwip = textToPixels.approximateScale
        guard pixelsPerTwip > 0 else {
            skipped += 1
            return
        }
        for run in runs {
            guard uniforms.count < movie.drawCapacity else {
                skipped += 1
                continue
            }
            let quadStart = glyphQuadCount
            let emPixels = max(1, min(256, Int((run.emTwips * pixelsPerTwip).rounded())))
            appendGlyphQuads(run: run, emPixels: emPixels, textToPixels: textToPixels)
            let quadCount = glyphQuadCount - quadStart
            guard quadCount > 0 else { continue }
            uniforms.append(makeUniforms(
                transform: pixelsToClip,
                fill: .solid(run.color),
                colorTransform: item.colorTransform,
                fillMode: .glyph
            ))
            ops.append(SWFDrawOp(
                kind: .content(clipCount: clipCount),
                usesGlyphBuffer: true,
                vertexStart: quadStart * 6,
                vertexCount: quadCount * 6,
                uniformIndex: uniforms.count - 1,
                bitmapId: nil,
                glyphCount: quadCount
            ))
        }
    }

    private mutating func appendGlyphQuads(
        run: SWFMovieResources.PlannedTextRun,
        emPixels: Int,
        textToPixels: SWFTransform
    ) {
        let font = run.font
        for glyph in run.glyphs {
            guard
                glyphQuadCount < movie.glyphQuadCapacity,
                glyph.glyphIndex >= 0, glyph.glyphIndex < font.glyphs.count
            else {
                skipped += 1
                continue
            }
            let entry = glyphAtlas.swfEntry(
                fontKey: run.fontKey, glyphIndex: glyph.glyphIndex, emPixelSize: emPixels
            ) {
                SWFGlyphPath.makePath(
                    segments: font.glyphs[glyph.glyphIndex].segments,
                    unitsPerEM: font.unitsPerEM,
                    emPixelSize: emPixels
                )
            }
            guard !entry.isEmpty else {
                // An outlined glyph with an empty atlas entry means the shared
                // atlas could not pack it (whitespace legitimately has none),
                // so it stays visible in the skipped tally instead of
                // disappearing quietly.
                if !font.glyphs[glyph.glyphIndex].segments.isEmpty {
                    skipped += 1
                }
                continue
            }
            let pen = textToPixels.apply(SIMD2(glyph.x, glyph.y))
            let minCorner = SIMD2(pen.x + entry.bearing.x, pen.y - entry.bearing.y)
            appendQuad(
                minCorner: minCorner,
                maxCorner: minCorner + entry.size,
                uvMin: entry.uvMin,
                uvMax: entry.uvMax
            )
            glyphQuadCount += 1
        }
    }

    private mutating func appendQuad(
        minCorner: SIMD2<Float>,
        maxCorner: SIMD2<Float>,
        uvMin: SIMD2<Float>,
        uvMax: SIMD2<Float>
    ) {
        let topLeft = SWFVertex(position: minCorner, uv: uvMin)
        let topRight = SWFVertex(
            position: SIMD2(maxCorner.x, minCorner.y), uv: SIMD2(uvMax.x, uvMin.y)
        )
        let bottomLeft = SWFVertex(
            position: SIMD2(minCorner.x, maxCorner.y), uv: SIMD2(uvMin.x, uvMax.y)
        )
        let bottomRight = SWFVertex(position: maxCorner, uv: uvMax)
        glyphVertices.append(contentsOf: [
            topLeft, topRight, bottomLeft, topRight, bottomRight, bottomLeft
        ])
    }

    /// Character-local twips -> NDC for one item.
    private func clipTransform(for item: SWFSceneItem) -> SWFTransform {
        pixelsToClip.concatenating(stageToPixels).concatenating(item.transform)
    }

    private func makeUniforms(
        transform: SWFTransform,
        fill: SWFMovieResources.ResolvedFill,
        colorTransform: SWFColorTransform,
        fillMode: SWFFillMode? = nil
    ) -> SWFDrawUniforms {
        var uniforms = SWFDrawUniforms()
        uniforms.transformRotation = transform.packedLinear
        uniforms.transformTranslation = transform.packedTranslation
        uniforms.colorMultiply = colorTransform.multiply
        uniforms.colorAdd = colorTransform.add
        switch fill {
        case let .solid(color):
            uniforms.baseColor = color
            uniforms.fillMode = UInt32((fillMode ?? .solid).rawValue)
        case let .bitmap(id, toUV, tiled):
            uniforms.fillMode = UInt32(SWFFillMode.bitmap.rawValue)
            uniforms.fillRotation = toUV.packedLinear
            uniforms.fillTranslation = toUV.packedTranslation
            uniforms.bitmapTiled = tiled ? 1 : 0
            uniforms.sourcePremultiplied = movie.bitmaps[id]?.premultiplied == true ? 1 : 0
        case let .gradient(row, toSquare, radial, spread):
            uniforms.fillMode = UInt32(
                (radial ? SWFFillMode.radialGradient : SWFFillMode.linearGradient).rawValue
            )
            uniforms.fillRotation = toSquare.packedLinear
            uniforms.fillTranslation = toSquare.packedTranslation
            uniforms.gradientSpread = UInt32(spread.rawValue)
            uniforms.gradientV = (Float(row) + 0.5) / Float(max(1, movie.gradientRowCount))
        }
        return uniforms
    }
}
