// Immediate-mode UI draw-list builder: a flat triangle list of `UIVertex`. Solid quads
// sample the atlas white texel, so one pipeline draws fills and text. Testable without Metal.

import OpenSkyShaderTypes
import simd

/// Result of applying the per-frame quad budget to a draw list.
nonisolated public struct UIBudgetResult: Sendable {
    public let vertices: [UIVertex]
    public let quads: Int
    public let dropped: Int
}

/// Last-frame UI accounting, mirrored to Renderer.lastUIDrawStats.
nonisolated public struct UIDrawStats: Equatable, Sendable {
    public var drawCalls = 0
    public var quads = 0
    public var glyphs = 0
    public var dropped = 0
    public var atlasWidth = 0
    public var atlasHeight = 0
    /// Glyph cells the shared atlas currently holds (system + SWF fonts).
    public var atlasGlyphs = 0
    /// Occupied fraction of the atlas, 0...1.
    public var atlasOccupancy: Float = 0
    /// Glyphs dropped because the atlas was full, since the last eviction. Non-zero means
    /// text is missing from the frame.
    public var atlasPackFailures = 0

    public init(
        drawCalls: Int = 0,
        quads: Int = 0,
        glyphs: Int = 0,
        dropped: Int = 0,
        atlasWidth: Int = 0,
        atlasHeight: Int = 0,
        atlasGlyphs: Int = 0,
        atlasOccupancy: Float = 0,
        atlasPackFailures: Int = 0
    ) {
        self.drawCalls = drawCalls
        self.quads = quads
        self.glyphs = glyphs
        self.dropped = dropped
        self.atlasWidth = atlasWidth
        self.atlasHeight = atlasHeight
        self.atlasGlyphs = atlasGlyphs
        self.atlasOccupancy = atlasOccupancy
        self.atlasPackFailures = atlasPackFailures
    }
}

nonisolated public struct UIDrawList: Sendable {
    /// Six vertices per quad (two triangles), no index buffer.
    public static let verticesPerQuad = 6

    public private(set) var vertices: [UIVertex] = []
    public private(set) var quadCount = 0
    public private(set) var glyphCount = 0
    public let whiteUV: SIMD2<Float>

    /// Appends one axis-aligned quad in pixel space with the given uv corners.
    public mutating func addQuad(
        rect: UIRect,
        uvMin: SIMD2<Float>,
        uvMax: SIMD2<Float>,
        color: SIMD4<Float>
    ) {
        let topLeft = UIVertex(position: SIMD2(rect.minX, rect.minY), uv: uvMin, color: color)
        let topRight = UIVertex(
            position: SIMD2(rect.maxX, rect.minY), uv: SIMD2(uvMax.x, uvMin.y), color: color
        )
        let bottomLeft = UIVertex(
            position: SIMD2(rect.minX, rect.maxY), uv: SIMD2(uvMin.x, uvMax.y), color: color
        )
        let bottomRight = UIVertex(position: SIMD2(rect.maxX, rect.maxY), uv: uvMax, color: color)
        vertices.append(topLeft)
        vertices.append(topRight)
        vertices.append(bottomLeft)
        vertices.append(topRight)
        vertices.append(bottomRight)
        vertices.append(bottomLeft)
        quadCount += 1
    }

    /// Filled rect: samples the white texel for full coverage.
    public mutating func fillRect(_ rect: UIRect, color: SIMD4<Float>) {
        guard rect.width > 0, rect.height > 0, color.w > 0 else { return }
        addQuad(rect: rect, uvMin: whiteUV, uvMax: whiteUV, color: color)
    }

    /// Inset border: four filled edge rects of `lineWidth` pixels.
    public mutating func strokeRect(_ rect: UIRect, lineWidth: Float, color: SIMD4<Float>) {
        guard lineWidth > 0, color.w > 0, rect.width > 0, rect.height > 0 else { return }
        let line = min(lineWidth, min(rect.width, rect.height) / 2)
        fillRect(UIRect(x: rect.minX, y: rect.minY, width: rect.width, height: line), color: color)
        fillRect(
            UIRect(x: rect.minX, y: rect.maxY - line, width: rect.width, height: line), color: color
        )
        let innerHeight = max(rect.height - 2 * line, 0)
        fillRect(
            UIRect(x: rect.minX, y: rect.minY + line, width: line, height: innerHeight),
            color: color
        )
        fillRect(
            UIRect(x: rect.maxX - line, y: rect.minY + line, width: line, height: innerHeight),
            color: color
        )
    }

    /// Text glyph quad: samples its coverage cell.
    public mutating func addGlyphQuad(
        rect: UIRect,
        uvMin: SIMD2<Float>,
        uvMax: SIMD2<Float>,
        color: SIMD4<Float>
    ) {
        guard rect.width > 0, rect.height > 0 else { return }
        addQuad(rect: rect, uvMin: uvMin, uvMax: uvMax, color: color)
        glyphCount += 1
    }

    /// Applies a hard per-frame quad budget. Returns the kept vertices, kept
    /// quad count, and the number of quads dropped past the cap (exact drop
    /// accounting, house style).
    public func budgeted(maxQuads: Int) -> UIBudgetResult {
        guard quadCount > maxQuads else {
            return UIBudgetResult(vertices: vertices, quads: quadCount, dropped: 0)
        }
        let kept = max(maxQuads, 0)
        return UIBudgetResult(
            vertices: Array(vertices.prefix(kept * Self.verticesPerQuad)),
            quads: kept,
            dropped: quadCount - kept
        )
    }
}
