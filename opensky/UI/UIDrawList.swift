// Immediate-mode UI draw-list builder (M8.1.1). Produces a flat triangle-list
// of UIVertex (pixel position, atlas uv, straight RGBA). Solid quads sample the
// atlas white texel so one pipeline draws fills, strokes, and text. Pure value
// type, unit-testable without Metal.

import simd

/// Result of applying the per-frame quad budget to a draw list.
struct UIBudgetResult {
    let vertices: [UIVertex]
    let quads: Int
    let dropped: Int
}

/// Last-frame UI accounting, mirrored to Renderer.lastUIDrawStats.
nonisolated struct UIDrawStats: Equatable {
    var drawCalls = 0
    var quads = 0
    var glyphs = 0
    var dropped = 0
    var atlasWidth = 0
    var atlasHeight = 0
}

struct UIDrawList {
    /// Six vertices per quad (two triangles), no index buffer.
    static let verticesPerQuad = 6

    private(set) var vertices: [UIVertex] = []
    private(set) var quadCount = 0
    private(set) var glyphCount = 0
    let whiteUV: SIMD2<Float>

    /// Appends one axis-aligned quad in pixel space with the given uv corners.
    mutating func addQuad(
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
    mutating func fillRect(_ rect: UIRect, color: SIMD4<Float>) {
        guard rect.width > 0, rect.height > 0, color.w > 0 else { return }
        addQuad(rect: rect, uvMin: whiteUV, uvMax: whiteUV, color: color)
    }

    /// Inset border: four filled edge rects of `lineWidth` pixels.
    mutating func strokeRect(_ rect: UIRect, lineWidth: Float, color: SIMD4<Float>) {
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
    mutating func addGlyphQuad(
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
    func budgeted(maxQuads: Int) -> UIBudgetResult {
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
