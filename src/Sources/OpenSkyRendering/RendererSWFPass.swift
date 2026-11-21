// SWF display-list encode: draws the movie's frame-1 commands over the 3D frame,
// before the dev UI. Each draw has a 256-byte uniform slot with the combined
// transform, fill mapping, and CXFORM. Shapes use the movie's twip-space vertex
// buffer; text uses the glyph-quad ring. Clip layers use a counting stencil.

public import Metal
import MetalKit
public import OpenSkyFormatsSWF
public import OpenSkyRenderCore
public import OpenSkyShaderTypes
import simd

extension Renderer {
    /// SWF layer A/B toggle. Off -> the layer encodes nothing and the frame
    /// matches a no-movie baseline exactly.
    public var swfEnabled: Bool {
        get { swf.enabled }
        set { swf.enabled = newValue }
    }

    /// Hides the HUD layer and keeps the others, as a loading screen hides the HUD
    /// under its own movie.
    public var swfHUDHidden: Bool {
        get { swf.hudHidden }
        set { swf.hudHidden = newValue }
    }

    /// Centered SWF presentation scale. The HUD acceptance readout uses this for
    /// live A/B checks without mutating the movie's display list.
    public var swfScale: Float {
        get { swf.scale }
        set {
            let finite = newValue.isFinite ? newValue : 1
            swf.scale = max(0.5, min(2, finite))
        }
    }

    /// Alpha over the HUD layer, 0 to 1: the HUD Opacity setting.
    public var swfOpacity: Float {
        get { swf.opacity }
        set { swf.opacity = newValue.isFinite ? min(max(newValue, 0), 1) : 1 }
    }

    /// Resolves `$TOKEN` text in every movie started after it is set.
    public var swfTextTranslator: ((String) -> String)? {
        get { swf.textTranslator }
        set {
            swf.textTranslator = newValue
            swf.runtime?.textTranslator = newValue
        }
    }

    /// Plays a menu movie's `PlaySound` descriptor; nil means `PlayOKSound`.
    /// Applies to movies started after it is set.
    public var swfSoundPlayer: (@MainActor (String?) -> Void)? {
        get { swf.soundPlayer }
        set { swf.soundPlayer = newValue }
    }

    /// Connected gamepads, told to every running and later movie. A gamepad
    /// switches the movies' button art to the gamepad platform.
    public var swfGamepadCount: Int {
        get { swf.gamepadCount }
        set {
            swf.gamepadCount = newValue
            swf.runtime?.setGamepadCount(newValue)
            swf.overlay?.runtime.setGamepadCount(newValue)
            swf.hud?.runtime.setGamepadCount(newValue)
        }
    }

    /// The movie package assigned via `setSWFMovie`; nil -> no SWF draws.
    var swfScene: SWFMovieScene? {
        swf.movie?.scene
    }

    /// SWF draw accounting from the most recently encoded frame.
    public var lastSWFDrawStats: SWFDrawStats {
        swf.lastDrawStats
    }

    /// Assigns (or clears) the movie the SWF layer renders. Builds the GPU
    /// package synchronously; the old package's allocations retire once
    /// in-flight frames drain. Main thread, between frames, like `setScene`.
    public func setSWFMovie(_ scene: SWFMovieScene?) throws {
        purgeRetiredResources()
        // A new movie invalidates any runtime driving the old one; the caller
        // starts a fresh one with `startSWFRuntime()`.
        swf.runtime = nil
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
            releaseSWFGlyphs(generation: old.generation)
        }
    }

    /// Hands one released movie's glyph cells back to the shared atlas, so swapped
    /// movies do not fill it. Safe between frames: both passes re-query the atlas,
    /// and the bumped revision re-uploads the texture.
    func releaseSWFGlyphs(generation: Int) {
        uiResources.glyphAtlas.releaseSWFGlyphs { fontKey in
            SWFMovieResources.TextPlanner.generation(forFontKey: fontKey) == generation
        }
    }

    /// Encodes the SWF layer into the open scene pass. Deterministic: the
    /// same movie and viewport produce the same command stream, uniforms, and
    /// glyph quads, so repeated frames are byte-identical.
    public func encodeSWF(descriptor: MTL4RenderPassDescriptor, state: inout ScenePassState) {
        var stats = SWFDrawStats()
        defer { swf.lastDrawStats = stats }
        guard swf.enabled else { return }
        let colorTexture = descriptor.colorAttachments[0].texture
        let viewport = SIMD2<Float>(
            Float(colorTexture?.width ?? 0), Float(colorTexture?.height ?? 0)
        )
        guard viewport.x > 0, viewport.y > 0 else { return }
        if !swf.hudHidden, let hud = swf.hud?.movie {
            encodeSWFMovie((hud, swf.opacity), viewport: viewport, state: &state, stats: &stats)
        }
        for movie in [swf.movie, swf.overlay?.movie].compactMap(\.self) {
            encodeSWFMovie((movie, 1), viewport: viewport, state: &state, stats: &stats)
        }
    }

    private func encodeSWFMovie(
        _ layer: (movie: SWFMovieResources, opacity: Float), viewport: SIMD2<Float>,
        state: inout ScenePassState, stats: inout SWFDrawStats
    ) {
        let movie = layer.movie
        var frame = SWFFrameBuilder(
            movie: movie,
            viewport: viewport,
            contentScale: swf.scale,
            glyphAtlas: uiResources.glyphAtlas
        )
        frame.opacity = layer.opacity
        frame.build()
        stats.skippedItems += frame.skipped + movie.buildSkipped
        uploadUIAtlasIfNeeded()
        guard !frame.ops.isEmpty else { return }
        writeSWFFrameData(frame: frame, movie: movie, slot: state.slot)
        encodeSWFOps(frame: frame, movie: movie, state: &state, stats: &stats)
    }

    private func writeSWFFrameData(frame: SWFFrameBuilder, movie: SWFMovieResources, slot: Int) {
        let uniformStride = Self.alignedSWFUniformsSize
        let uniformBase = slot * max(1, movie.drawCapacity) * uniformStride
        let contents = unsafe movie.uniformBuffer.contents()
        for (index, var uniforms) in frame.uniforms.enumerated() {
            unsafe contents.advanced(by: uniformBase + index * uniformStride)
                .copyMemory(from: &uniforms, byteCount: MemoryLayout<SWFDrawUniforms>.size)
        }
        let glyphBase = slot * max(1, movie.glyphQuadCapacity) * 6
            * MemoryLayout<SWFVertex>.stride
        frame.glyphVertices.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            unsafe movie.glyphVertexBuffer.contents().advanced(by: glyphBase)
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
            case let .content(clipCount, additive):
                encoder.setRenderPipelineState(
                    additive ? swf.additivePipeline ?? swf.contentPipeline : swf.contentPipeline
                )
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
nonisolated struct SWFDrawOp: Sendable {
    enum Kind: Sendable {
        case content(clipCount: Int, additive: Bool)
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
    /// Multiplies every draw's alpha: the HUD Opacity setting.
    var opacity: Float = 1

    init(
        movie: SWFMovieResources,
        viewport: SIMD2<Float>,
        contentScale: Float,
        glyphAtlas: UIGlyphAtlas
    ) {
        self.movie = movie
        self.glyphAtlas = glyphAtlas
        stageToPixels = SWFViewportMapping.twipsToPixels(
            frameSize: movie.scene.movie.frameSize,
            viewportPixels: viewport,
            contentScale: contentScale
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
            var drawUniforms = makeUniforms(
                transform: transform,
                fill: run.fill,
                colorTransform: item.colorTransform
            )
            if let grid = item.scalingGrid {
                drawUniforms.scaleGrid = grid.grid
                drawUniforms.scaleGridBounds = grid.bounds
                drawUniforms.scaleGridScale = grid.scale
            }
            uniforms.append(drawUniforms)
            let bitmapId: UInt16? = if case let .bitmap(id, _, _) = run.fill {
                id
            } else {
                nil
            }
            ops.append(SWFDrawOp(
                kind: .content(clipCount: clipCount, additive: item.isAdditive),
                usesGlyphBuffer: false,
                vertexStart: run.vertexStart,
                vertexCount: run.vertexCount,
                uniformIndex: uniforms.count - 1,
                bitmapId: bitmapId,
                glyphCount: 0
            ))
        }
    }

    /// Text draws: glyphs rasterize upright at the on-screen pixel size, and each quad's
    /// corners follow the transform's rotation and skew (`SWFTextQuad`).
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
            if quadCount > 0 {
                uniforms.append(makeUniforms(
                    transform: pixelsToClip,
                    fill: .solid(run.color),
                    colorTransform: item.colorTransform,
                    fillMode: .glyph
                ))
                ops.append(SWFDrawOp(
                    kind: .content(clipCount: clipCount, additive: item.isAdditive),
                    usesGlyphBuffer: true,
                    vertexStart: quadStart * 6,
                    vertexCount: quadCount * 6,
                    uniformIndex: uniforms.count - 1,
                    bitmapId: nil,
                    glyphCount: quadCount
                ))
            }
            appendInlineImages(run, item: item, clipCount: clipCount, textToPixels: textToPixels)
        }
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
        uniforms.colorMultiply = colorTransform.multiply * SIMD4(1, 1, 1, opacity)
        uniforms.colorAdd = colorTransform.add * SIMD4(1, 1, 1, opacity)
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
        case let .gradient(row, toSquare, radial, focal, spread):
            let mode: SWFFillMode = focal != nil
                ? .focalRadialGradient : radial ? .radialGradient : .linearGradient
            uniforms.fillMode = UInt32(mode.rawValue)
            uniforms.gradientFocal = focal ?? 0
            uniforms.fillRotation = toSquare.packedLinear
            uniforms.fillTranslation = toSquare.packedTranslation
            uniforms.gradientSpread = UInt32(spread.rawValue)
            uniforms.gradientV = (Float(row) + 0.5) / Float(max(1, movie.gradientRowCount))
        }
        return uniforms
    }
}

nonisolated extension SWFFrameBuilder {
    /// An HTML field's `<img>` pictures: one bitmap quad each in the glyph ring, cut at the
    /// field's bottom edge like the glyphs.
    private mutating func appendInlineImages(
        _ run: SWFMovieResources.PlannedTextRun,
        item: SWFSceneItem,
        clipCount: Int,
        textToPixels: SWFTransform
    ) {
        let twipsPerPixel: Float = 20
        let scale = textToPixels.approximateScale
        let shape = SWFTextQuad.shape(of: textToPixels)
        for placement in run.inlineImages {
            guard
                let id = movie.scene.movie.exportedNames[placement.image.source],
                movie.bitmaps[id] != nil,
                uniforms.count < movie.drawCapacity,
                glyphQuadCount < movie.glyphQuadCapacity
            else {
                skipped += 1
                continue
            }
            let anchor = SIMD2(placement.x, placement.y)
            let origin = textToPixels.apply(anchor)
            let size = SIMD2(placement.image.width, placement.image.height) * twipsPerPixel * scale
            guard size.x > 0, size.y > 0 else { continue }
            let bottom = run.clipBottom.map { ($0 - anchor.y) * scale }
            // The shader reads the bitmap at the pixel position mapped to 0...1 of the picture.
            guard
                let quad = SWFTextQuad(
                    origin: origin, shape: shape, localMin: .zero, localMax: size,
                    localBottom: bottom, uvMin: .zero, uvMax: .one
                ),
                let toUV = SWFTextQuad.pixelsToUnit(
                    origin: origin, shape: shape, localMin: .zero, localSize: size
                )
            else { continue }
            let quadStart = glyphQuadCount
            glyphVertices.append(contentsOf: quad.vertices)
            glyphQuadCount += 1
            uniforms.append(makeUniforms(
                transform: pixelsToClip,
                fill: .bitmap(characterId: id, toUV: toUV, tiled: false),
                colorTransform: item.colorTransform
            ))
            ops.append(SWFDrawOp(
                kind: .content(clipCount: clipCount, additive: item.isAdditive),
                usesGlyphBuffer: true,
                vertexStart: quadStart * 6,
                vertexCount: 6,
                uniformIndex: uniforms.count - 1,
                bitmapId: id,
                glyphCount: 0
            ))
        }
    }

    private mutating func appendGlyphQuads(
        run: SWFMovieResources.PlannedTextRun,
        emPixels: Int,
        textToPixels: SWFTransform
    ) {
        let font = run.font
        let scale = textToPixels.approximateScale
        let shape = SWFTextQuad.shape(of: textToPixels)
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
            let localMin = SIMD2(entry.bearing.x, -entry.bearing.y)
            // A line the field's bottom edge cuts shows only its top part, as in Flash.
            guard
                let quad = SWFTextQuad(
                    origin: textToPixels.apply(SIMD2(glyph.x, glyph.y)),
                    shape: shape,
                    localMin: localMin,
                    localMax: localMin + entry.size,
                    localBottom: run.clipBottom.map { ($0 - glyph.y) * scale },
                    uvMin: entry.uvMin,
                    uvMax: entry.uvMax
                )
            else { continue }
            glyphVertices.append(contentsOf: quad.vertices)
            glyphQuadCount += 1
        }
    }
}
