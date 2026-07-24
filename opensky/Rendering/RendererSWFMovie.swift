// Per-movie GPU package for the SWF layer: every dictionary shape
// tessellated into one static twip-space vertex buffer (with per-fill run
// table), bitmap characters uploaded as rgba8 textures, gradient fills baked
// into a ramp atlas (one 256-texel row per gradient), text placements
// pre-laid-out in twips, and the triple-buffered per-draw uniform + glyph
// vertex rings sized exactly for the frame-1 command stream. Swapped as a
// unit by `Renderer.setSWFMovie`; encode lives in RendererSWFPass.swift.

import Metal
import simd

nonisolated final class SWFMovieResources {
    /// A shape fill resolved to renderer terms at build time.
    enum ResolvedFill {
        case solid(SIMD4<Float>)
        /// `toUV` maps shape-local twips to normalized texture coordinates.
        case bitmap(characterId: UInt16, toUV: SWFTransform, tiled: Bool)
        /// `toSquare` maps shape-local twips to the -1..1 gradient square.
        case gradient(row: Int, toSquare: SWFTransform, radial: Bool, spread: SWFGradientSpread)
    }

    struct RunEntry {
        let vertexStart: Int
        let vertexCount: Int
        let fill: ResolvedFill
    }

    /// One shape's slice of the shared vertex buffer. The whole range backs
    /// mask draws; the runs back per-fill content draws.
    struct ShapeEntry {
        let vertexStart: Int
        let vertexCount: Int
        let runs: [RunEntry]
    }

    struct BitmapEntry {
        let texture: MTLTexture
        let premultiplied: Bool
    }

    /// One text draw planned at build time: resolved font, atlas key, and the
    /// twip-space glyph placements (viewport-independent).
    struct PlannedTextRun {
        let font: SWFFontDefinition
        let fontKey: Int
        let emTwips: Float
        let color: SIMD4<Float>
        let glyphs: [SWFGlyphPlacement]
    }

    let scene: SWFMovieScene
    let commands: [SWFSceneCommand]
    let shapes: [UInt16: ShapeEntry]
    let bitmaps: [UInt16: BitmapEntry]
    /// nil when the movie has no gradient fills (fallback ramp binds instead).
    let gradientTexture: MTLTexture?
    let gradientRowCount: Int
    /// Command index -> planned text runs for text draws.
    let textPlans: [Int: [PlannedTextRun]]
    let vertexBuffer: MTLBuffer
    let glyphVertexBuffer: MTLBuffer
    let uniformBuffer: MTLBuffer
    /// Per-frame draw slots in the uniform ring (exact for the command
    /// stream; encode counts anything beyond it as skipped).
    let drawCapacity: Int
    let glyphQuadCapacity: Int
    /// Fills/texts unresolvable at build (missing fonts, degenerate
    /// matrices); folded into the per-frame skipped stat.
    let buildSkipped: Int

    var residencyAllocations: [MTLAllocation] {
        var allocations: [MTLAllocation] = [vertexBuffer, glyphVertexBuffer, uniformBuffer]
        allocations.append(contentsOf: bitmaps.values.map(\.texture))
        if let gradientTexture {
            allocations.append(gradientTexture)
        }
        return allocations
    }

    init(device: MTLDevice, scene: SWFMovieScene, generation: Int) throws {
        self.scene = scene
        let flattened = SWFScene.build(movie: scene.movie)
        commands = flattened.commands
        var builder = SWFMovieBuilder(scene: scene, generation: generation)
        builder.buildShapes()
        builder.buildTextPlans(commands: commands)
        shapes = builder.shapes
        textPlans = builder.textPlans
        gradientRowCount = builder.gradientRows.count
        buildSkipped = builder.skipped + flattened.skippedPlacements
        bitmaps = try Self.makeBitmapTextures(device: device, movie: scene.movie)
        gradientTexture = try Self.makeGradientTexture(device: device, rows: builder.gradientRows)
        let capacities = Self.capacities(commands: commands, shapes: shapes, plans: textPlans)
        drawCapacity = capacities.draws
        glyphQuadCapacity = capacities.glyphs
        vertexBuffer = try Self.makeVertexBuffer(
            device: device, vertices: builder.vertices, label: "SWFShapeVertices"
        )
        glyphVertexBuffer = try Renderer.makeUniformBuffer(
            device: device,
            length: max(1, capacities.glyphs) * 6 * MemoryLayout<SWFVertex>.stride
                * Renderer.maxFramesInFlight,
            label: "SWFGlyphVertices"
        )
        uniformBuffer = try Renderer.makeUniformBuffer(
            device: device,
            length: max(1, capacities.draws) * Renderer.alignedSWFUniformsSize
                * Renderer.maxFramesInFlight,
            label: "SWFDrawUniforms"
        )
    }

    /// Exact per-frame draw + glyph-quad upper bounds for the command stream.
    private static func capacities(
        commands: [SWFSceneCommand],
        shapes: [UInt16: ShapeEntry],
        plans: [Int: [PlannedTextRun]]
    ) -> (draws: Int, glyphs: Int) {
        var draws = 0
        var glyphs = 0
        for (index, command) in commands.enumerated() {
            switch command {
            case let .beginClip(masks), let .endClip(masks):
                draws += masks.count
            case let .draw(item, _):
                switch item.content {
                case let .shape(id):
                    draws += shapes[id]?.runs.count ?? 0
                case .staticText, .editText:
                    let runs = plans[index] ?? []
                    draws += runs.count
                    glyphs += runs.reduce(0) { $0 + $1.glyphs.count }
                }
            }
        }
        return (draws, glyphs)
    }

    private static func makeVertexBuffer(
        device: MTLDevice,
        vertices: [SWFVertex],
        label: String
    ) throws -> MTLBuffer {
        let length = max(1, vertices.count) * MemoryLayout<SWFVertex>.stride
        let buffer = try Renderer.makeUniformBuffer(device: device, length: length, label: label)
        vertices.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            buffer.contents().copyMemory(from: base, byteCount: bytes.count)
        }
        return buffer
    }

    private static func makeBitmapTextures(
        device: MTLDevice,
        movie: SWFMovie
    ) throws -> [UInt16: BitmapEntry] {
        var result: [UInt16: BitmapEntry] = [:]
        for id in movie.characters.keys.sorted() {
            guard
                case let .bitmap(bitmap) = movie.characters[id],
                bitmap.width > 0, bitmap.height > 0 else { continue }
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .rgba8Unorm,
                width: bitmap.width,
                height: bitmap.height,
                mipmapped: false
            )
            descriptor.usage = .shaderRead
            descriptor.storageMode = .shared
            guard let texture = device.makeTexture(descriptor: descriptor) else {
                throw RendererError.textureAllocationFailed
            }
            texture.label = "SWFBitmap\(id)"
            bitmap.pixels.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                texture.replace(
                    region: MTLRegionMake2D(0, 0, bitmap.width, bitmap.height),
                    mipmapLevel: 0,
                    withBytes: base,
                    bytesPerRow: bitmap.width * 4
                )
            }
            result[id] = BitmapEntry(texture: texture, premultiplied: bitmap.premultipliedAlpha)
        }
        return result
    }

    /// One 256-texel row per gradient fill, colors linearly interpolated
    /// between the GRADRECORD stops (pad at the ends). The linearRGB
    /// interpolation mode is treated as normal RGB (documented deferral).
    private static func makeGradientTexture(
        device: MTLDevice,
        rows: [SWFGradient]
    ) throws -> MTLTexture? {
        guard !rows.isEmpty else { return nil }
        let width = 256
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: width, height: rows.count, mipmapped: false
        )
        descriptor.usage = .shaderRead
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw RendererError.textureAllocationFailed
        }
        texture.label = "SWFGradientRamp"
        var pixels = [UInt8](repeating: 0, count: width * rows.count * 4)
        for (row, gradient) in rows.enumerated() {
            writeRampRow(gradient, into: &pixels, row: row, width: width)
        }
        pixels.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress else { return }
            texture.replace(
                region: MTLRegionMake2D(0, 0, width, rows.count),
                mipmapLevel: 0,
                withBytes: base,
                bytesPerRow: width * 4
            )
        }
        return texture
    }

    private static func writeRampRow(
        _ gradient: SWFGradient,
        into pixels: inout [UInt8],
        row: Int,
        width: Int
    ) {
        let stops = gradient.records.sorted { $0.ratio < $1.ratio }
        for texel in 0 ..< width {
            let ratio = Float(texel) / Float(width - 1) * 255
            let color = interpolatedColor(stops: stops, ratio: ratio)
            let base = (row * width + texel) * 4
            pixels[base] = color.red
            pixels[base + 1] = color.green
            pixels[base + 2] = color.blue
            pixels[base + 3] = color.alpha
        }
    }

    private static func interpolatedColor(
        stops: [SWFGradientRecord],
        ratio: Float
    ) -> SWFColor {
        guard let first = stops.first else {
            return SWFColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        var previous = first
        for stop in stops {
            if ratio <= Float(stop.ratio) {
                let span = Float(stop.ratio) - Float(previous.ratio)
                guard span > 0 else { return stop.color }
                let fraction = (ratio - Float(previous.ratio)) / span
                return blend(previous.color, stop.color, fraction: fraction)
            }
            previous = stop
        }
        return previous.color
    }

    private static func blend(
        _ from: SWFColor,
        _ to: SWFColor,
        fraction: Float
    ) -> SWFColor {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            UInt8(max(0, min(255, (Float(a) + (Float(b) - Float(a)) * fraction).rounded())))
        }
        return SWFColor(
            red: mix(from.red, to.red),
            green: mix(from.green, to.green),
            blue: mix(from.blue, to.blue),
            alpha: mix(from.alpha, to.alpha)
        )
    }
}

/// CPU-side build pass: tessellates shapes into the shared vertex list,
/// resolves fills (collecting gradient rows), and plans text runs.
private struct SWFMovieBuilder {
    let scene: SWFMovieScene
    let generation: Int
    var vertices: [SWFVertex] = []
    var shapes: [UInt16: SWFMovieResources.ShapeEntry] = [:]
    var gradientRows: [SWFGradient] = []
    var textPlans: [Int: [SWFMovieResources.PlannedTextRun]] = [:]
    var skipped = 0
    private var externalFontKeys: [String: Int] = [:]
    private let shapeCache = SWFShapeCache()

    init(scene: SWFMovieScene, generation: Int) {
        self.scene = scene
        self.generation = generation
    }

    /// Gradient square half-extent in twips (spec chapter 7, p. 134).
    private static let gradientSquareHalfExtent: Float = 16384

    mutating func buildShapes() {
        let movie = scene.movie
        for id in movie.characters.keys.sorted() {
            guard case let .shape(shape) = movie.characters[id] else { continue }
            let mesh = shapeCache.mesh(for: shape)
            let start = vertices.count
            vertices.append(contentsOf: mesh.vertices.map {
                SWFVertex(position: $0, uv: .zero)
            })
            var runs: [SWFMovieResources.RunEntry] = []
            for run in mesh.runs {
                guard
                    run.fillStyleIndex >= 1,
                    run.fillStyleIndex <= shape.fillStyles.count,
                    let fill = resolveFill(shape.fillStyles[run.fillStyleIndex - 1])
                else {
                    skipped += 1
                    continue
                }
                runs.append(SWFMovieResources.RunEntry(
                    vertexStart: start + run.triangleRange.lowerBound * 3,
                    vertexCount: run.triangleRange.count * 3,
                    fill: fill
                ))
            }
            shapes[id] = SWFMovieResources.ShapeEntry(
                vertexStart: start, vertexCount: mesh.vertices.count, runs: runs
            )
        }
    }

    /// Resolves one FILLSTYLE to renderer terms; nil for degenerate fill
    /// matrices (counted as skipped). Focal radial gradients render as plain
    /// radial (the FIXED8 focal point is ignored — documented deferral).
    private mutating func resolveFill(_ style: SWFFillStyle) -> SWFMovieResources.ResolvedFill? {
        switch style {
        case let .solid(color):
            return .solid(Self.straightColor(color))
        case let .bitmap(characterId, matrix, tiled, _):
            guard
                let bitmap = scene.movie.bitmap(characterId),
                bitmap.width > 0, bitmap.height > 0,
                let inverse = SWFTransform(matrix: matrix).inverted else { return nil }
            let toUV = SWFTransform(
                scaleX: 1 / Float(bitmap.width), scaleY: 1 / Float(bitmap.height)
            ).concatenating(inverse)
            return .bitmap(characterId: characterId, toUV: toUV, tiled: tiled)
        case let .linearGradient(matrix, gradient),
             let .radialGradient(matrix, gradient),
             let .focalRadialGradient(matrix, gradient):
            guard let inverse = SWFTransform(matrix: matrix).inverted else { return nil }
            let toSquare = SWFTransform(
                scaleX: 1 / Self.gradientSquareHalfExtent,
                scaleY: 1 / Self.gradientSquareHalfExtent
            ).concatenating(inverse)
            let radial = if case .linearGradient = style {
                false
            } else {
                true
            }
            gradientRows.append(gradient)
            return .gradient(
                row: gradientRows.count - 1,
                toSquare: toSquare,
                radial: radial,
                spread: Self.spread(gradient.spreadMode)
            )
        }
    }

    mutating func buildTextPlans(commands: [SWFSceneCommand]) {
        for (index, command) in commands.enumerated() {
            guard case let .draw(item, _) = command else { continue }
            switch item.content {
            case .shape:
                continue
            case let .staticText(id):
                guard let text = scene.movie.staticText(id) else { continue }
                textPlans[index] = planStaticText(text)
            case let .editText(id):
                guard let text = scene.movie.editText(id) else { continue }
                textPlans[index] = planEditText(text)
            }
        }
    }

    private mutating func planStaticText(_ text: SWFTextDefinition)
        -> [SWFMovieResources.PlannedTextRun]
    {
        var planned: [SWFMovieResources.PlannedTextRun] = []
        for run in SWFTextLayout.staticText(text).runs {
            guard
                let fontID = run.fontID, let font = scene.movie.font(fontID),
                !font.glyphs.isEmpty
            else {
                skipped += 1
                continue
            }
            planned.append(SWFMovieResources.PlannedTextRun(
                font: font,
                fontKey: internalFontKey(fontID),
                emTwips: run.emTwips,
                color: Self.straightColor(run.color),
                glyphs: run.glyphs
            ))
        }
        return planned
    }

    private mutating func planEditText(_ text: SWFEditText)
        -> [SWFMovieResources.PlannedTextRun]
    {
        guard text.plainText?.isEmpty == false else { return [] }
        guard let font = scene.resolvedFont(for: text) else {
            skipped += 1
            return []
        }
        let layout = SWFTextLayout.editText(text, font: font)
        return layout.runs.map { run in
            SWFMovieResources.PlannedTextRun(
                font: font,
                fontKey: fontKey(for: font, editText: text),
                emTwips: run.emTwips,
                color: Self.straightColor(run.color),
                glyphs: run.glyphs
            )
        }
    }

    /// Atlas key namespace: bits 0-15 the internal font id, bit 17 the
    /// external-substitution flag, bits 18+ the movie generation. Unique per
    /// (loaded movie, font) as the shared atlas cache requires.
    private func internalFontKey(_ fontID: UInt16) -> Int {
        (generation << 18) | Int(fontID)
    }

    private mutating func fontKey(for font: SWFFontDefinition, editText: SWFEditText) -> Int {
        if
            let fontID = editText.fontID, let internalFont = scene.movie.font(fontID),
            !internalFont.glyphs.isEmpty
        {
            return internalFontKey(fontID)
        }
        let name = font.name
        if let existing = externalFontKeys[name] {
            return existing
        }
        let key = (generation << 18) | 0x20000 | externalFontKeys.count
        externalFontKeys[name] = key
        return key
    }

    private static func straightColor(_ color: SWFColor) -> SIMD4<Float> {
        SIMD4(
            Float(color.red) / 255,
            Float(color.green) / 255,
            Float(color.blue) / 255,
            Float(color.alpha) / 255
        )
    }

    private static func spread(_ mode: SWFGradient.SpreadMode) -> SWFGradientSpread {
        switch mode {
        case .pad, .reserved: .pad
        case .reflect: .reflect
        case .repeating: .repeat
        }
    }
}
