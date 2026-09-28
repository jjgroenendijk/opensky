// Per-movie GPU package for the SWF layer: every dictionary shape tessellated
// into one static twip-space vertex buffer (with per-fill run table), bitmap
// characters uploaded as rgba8 textures, gradient fills baked into a ramp
// atlas (one 256-texel row per gradient), and the triple-buffered per-draw
// uniform + glyph vertex rings. Swapped as a unit by `Renderer.setSWFMovie`;
// encode lives in RendererSWFPass.swift; the static build pass lives in
// RendererSWFBuild.swift.
//
// M8.3.2 makes the per-frame half mutable. The command stream and its text
// plans are replaced by `update(scene:device:)` whenever the AS2 runtime
// changes the display list, while the shapes, textures, ramp, and glyph atlas
// are retained — rebuilding those per frame is what made `setSWFMovie` far too
// heavy to call from a frame loop. The rings are sized with headroom and grow
// (never shrink) rather than overflowing when a movie places more than frame 1
// held.

import Metal
import OpenSkyShaderTypes
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

    /// One text draw planned for the current command stream: resolved font,
    /// atlas key, and the twip-space glyph placements (viewport-independent).
    struct PlannedTextRun {
        let font: SWFFontDefinition
        let fontKey: Int
        let emTwips: Float
        let color: SIMD4<Float>
        let glyphs: [SWFGlyphPlacement]
    }

    let scene: SWFMovieScene
    /// Namespaces this package's glyph-atlas font keys, so releasing the
    /// package can evict exactly its glyphs from the shared atlas.
    let generation: Int
    /// The current draw-command stream: frame 1 at build, then whatever the AS2
    /// runtime last produced.
    private(set) var commands: [SWFSceneCommand]
    let shapes: [UInt16: ShapeEntry]
    let bitmaps: [UInt16: BitmapEntry]
    /// nil when the movie has no gradient fills (fallback ramp binds instead).
    let gradientTexture: MTLTexture?
    let gradientRowCount: Int
    /// Command index -> planned text runs for text draws.
    private(set) var textPlans: [Int: [PlannedTextRun]]
    let vertexBuffer: MTLBuffer
    private(set) var glyphVertexBuffer: MTLBuffer
    private(set) var uniformBuffer: MTLBuffer
    /// Per-frame draw slots in the uniform ring. Headroomed over the current
    /// stream so an ordinary display-list change needs no reallocation; encode
    /// counts anything beyond it as skipped.
    private(set) var drawCapacity: Int
    private(set) var glyphQuadCapacity: Int
    /// Fills/texts unresolvable when the current stream was planned (missing
    /// fonts, degenerate matrices) plus the flattener's own skips; folded into
    /// the per-frame skipped stat.
    private(set) var buildSkipped: Int

    /// Skips owned by the static shape build, which updates never revisit.
    private let shapeSkipped: Int
    private let planner: SWFTextPlanner

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
        self.generation = generation
        let flattened = SWFScene.build(movie: scene.movie)
        commands = flattened.commands
        var builder = SWFMovieShapeBuilder(scene: scene)
        builder.buildShapes()
        shapes = builder.shapes
        shapeSkipped = builder.skipped
        planner = SWFTextPlanner(scene: scene, generation: generation)
        textPlans = planner.plan(commands: flattened.commands)
        gradientRowCount = builder.gradientRows.count
        buildSkipped = builder.skipped + planner.skipped + flattened.skippedPlacements
        bitmaps = try SWFMovieTextures.makeBitmaps(device: device, movie: scene.movie)
        gradientTexture = try SWFMovieTextures.makeGradientRamp(
            device: device, rows: builder.gradientRows
        )
        let needed = Self.capacities(
            commands: flattened.commands, shapes: builder.shapes, plans: textPlans
        )
        drawCapacity = Self.headroom(needed.draws)
        glyphQuadCapacity = Self.headroom(needed.glyphs)
        vertexBuffer = try Self.makeVertexBuffer(
            device: device, vertices: builder.vertices, label: "SWFShapeVertices"
        )
        glyphVertexBuffer = try Self.makeGlyphBuffer(device: device, capacity: glyphQuadCapacity)
        uniformBuffer = try Self.makeUniformRing(device: device, capacity: drawCapacity)
    }

    /// Replaces the command stream and its text plans, growing the rings when
    /// the new stream needs more slots than the old one. Returns the buffers
    /// the caller must retire (empty when nothing grew), so the renderer can
    /// keep them alive until in-flight frames drain.
    func update(scene newScene: SWFScene, device: MTLDevice) throws -> [MTLAllocation] {
        let plans = planner.plan(commands: newScene.commands)
        let needed = Self.capacities(
            commands: newScene.commands, shapes: shapes, plans: plans
        )
        var retiring: [MTLAllocation] = []
        if needed.draws > drawCapacity {
            let capacity = Self.headroom(needed.draws)
            let buffer = try Self.makeUniformRing(device: device, capacity: capacity)
            retiring.append(uniformBuffer)
            uniformBuffer = buffer
            drawCapacity = capacity
        }
        if needed.glyphs > glyphQuadCapacity {
            let capacity = Self.headroom(needed.glyphs)
            let buffer = try Self.makeGlyphBuffer(device: device, capacity: capacity)
            retiring.append(glyphVertexBuffer)
            glyphVertexBuffer = buffer
            glyphQuadCapacity = capacity
        }
        commands = newScene.commands
        textPlans = plans
        buildSkipped = shapeSkipped + planner.skipped + newScene.skippedPlacements
        return retiring
    }

    /// Ring slots for a stream that needs `count`: half again, never below a
    /// floor, so ordinary display-list churn never reallocates.
    static func headroom(_ count: Int) -> Int {
        max(64, count + count / 2)
    }

    /// Exact per-frame draw + glyph-quad upper bounds for a command stream.
    static func capacities(
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

    private static func makeUniformRing(device: MTLDevice, capacity: Int) throws -> MTLBuffer {
        try Renderer.makeUniformBuffer(
            device: device,
            length: max(1, capacity) * Renderer.alignedSWFUniformsSize
                * Renderer.maxFramesInFlight,
            label: "SWFDrawUniforms"
        )
    }

    private static func makeGlyphBuffer(device: MTLDevice, capacity: Int) throws -> MTLBuffer {
        try Renderer.makeUniformBuffer(
            device: device,
            length: max(1, capacity) * 6 * MemoryLayout<SWFVertex>.stride
                * Renderer.maxFramesInFlight,
            label: "SWFGlyphVertices"
        )
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
}
