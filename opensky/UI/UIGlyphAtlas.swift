// CPU shelf-packed single-channel glyph atlas (M8.1.1). Rasterizes glyphs via
// CoreGraphics into an r8 coverage bitmap the renderer uploads to an r8Unorm
// texture. A reserved solid-white texel backs untextured quads so one pipeline
// draws fills + text. Font smoothing is disabled -> same-process renders are
// byte-deterministic. Glyph cache keyed by font + glyph id + pixel size.

import CoreGraphics
import CoreText
import simd

/// Cache key: font discriminator + glyph id + integer pixel size.
struct UIGlyphKey: Hashable {
    let fontKey: Int
    let glyphID: UInt16
    let pixelSize: Int
}

/// A packed glyph's atlas placement + placement metrics, all in pixels.
struct UIGlyphEntry: Equatable {
    /// Atlas UV of the coverage cell (top-left, bottom-right), normalized.
    let uvMin: SIMD2<Float>
    let uvMax: SIMD2<Float>
    /// Coverage cell pixel size.
    let size: SIMD2<Float>
    /// x: left side bearing; y: height of the cell above the baseline.
    let bearing: SIMD2<Float>

    static let empty = UIGlyphEntry(uvMin: .zero, uvMax: .zero, size: .zero, bearing: .zero)

    /// Whitespace / zero-area glyph -> emits no quad.
    var isEmpty: Bool {
        size.x <= 0 || size.y <= 0
    }
}

final class UIGlyphAtlas {
    static let dimension = 512
    private static let padding = 1
    private static let whiteBlock = 4

    let width = dimension
    let height = dimension
    /// Coverage bytes, row-major, top-left origin (matches Metal texture v-down).
    private(set) var pixels: [UInt8]
    /// Bumped whenever new glyphs pack -> the renderer re-uploads the texture.
    private(set) var revision = 0
    /// UV of a fully-opaque texel; solid fills sample it for coverage == 1.
    let whiteUV: SIMD2<Float>

    private var cache: [UIGlyphKey: UIGlyphEntry] = [:]
    private var shelfX = 0
    private var shelfY: Int
    private var shelfHeight = 0

    init() {
        pixels = [UInt8](repeating: 0, count: Self.dimension * Self.dimension)
        // Reserve a solid-white block top-left for untextured quads.
        for row in 0 ..< Self.whiteBlock {
            for col in 0 ..< Self.whiteBlock {
                pixels[row * Self.dimension + col] = 255
            }
        }
        whiteUV = SIMD2(
            Float(Self.whiteBlock) / 2 / Float(Self.dimension),
            Float(Self.whiteBlock) / 2 / Float(Self.dimension)
        )
        shelfY = Self.whiteBlock + Self.padding
    }

    /// Returns the cached entry for a glyph, rasterizing + packing on first use.
    /// `ctFont` must be built at `pixelSize` (same font `fontKey` identifies).
    func entry(fontKey: Int, glyphID: CGGlyph, pixelSize: Int, ctFont: CTFont) -> UIGlyphEntry {
        let key = UIGlyphKey(fontKey: fontKey, glyphID: UInt16(glyphID), pixelSize: pixelSize)
        if let cached = cache[key] {
            return cached
        }
        let packed = rasterize(glyphID: glyphID, ctFont: ctFont)
        cache[key] = packed
        return packed
    }

    /// A glyph's tight coverage cell: pixel size + the draw origin (offset that
    /// shifts the baseline-relative bbox into the cell) + the left/top bearings.
    private struct GlyphBox {
        let width: Int
        let height: Int
        let drawX: Int
        let drawY: Int
        let bearingX: Int
        let bearingY: Int
    }

    private func rasterize(glyphID: CGGlyph, ctFont: CTFont) -> UIGlyphEntry {
        var glyph = glyphID
        let bounds = CTFontGetBoundingRectsForGlyphs(ctFont, .default, &glyph, nil, 1)
        guard bounds.width > 0, bounds.height > 0, !bounds.isNull, !bounds.isInfinite else {
            return .empty
        }
        let minX = Int((bounds.minX).rounded(.down)) - Self.padding
        let minY = Int((bounds.minY).rounded(.down)) - Self.padding
        let maxX = Int((bounds.maxX).rounded(.up)) + Self.padding
        let maxY = Int((bounds.maxY).rounded(.up)) + Self.padding
        // maxY is the cell top's height above the baseline (CG y-up).
        let box = GlyphBox(
            width: maxX - minX, height: maxY - minY,
            drawX: -minX, drawY: -minY, bearingX: minX, bearingY: maxY
        )
        guard
            box.width > 0, box.height > 0,
            let coverage = renderCoverage(glyph: glyph, ctFont: ctFont, box: box),
            let placement = pack(cellWidth: box.width, cellHeight: box.height, coverage: coverage)
        else { return .empty }
        return UIGlyphEntry(
            uvMin: SIMD2(Float(placement.x) / Float(width), Float(placement.y) / Float(height)),
            uvMax: SIMD2(
                Float(placement.x + box.width) / Float(width),
                Float(placement.y + box.height) / Float(height)
            ),
            size: SIMD2(Float(box.width), Float(box.height)),
            bearing: SIMD2(Float(box.bearingX), Float(box.bearingY))
        )
    }

    /// Draws the glyph white-on-black into a tight grayscale bitmap, returning
    /// its coverage bytes (top-left origin). Font smoothing off for determinism.
    private func renderCoverage(glyph: CGGlyph, ctFont: CTFont, box: GlyphBox) -> [UInt8]? {
        guard
            let context = CGContext(
                data: nil,
                width: box.width,
                height: box.height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return nil }
        context.setShouldAntialias(true)
        context.setShouldSmoothFonts(false)
        context.setAllowsFontSmoothing(false)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        var mutableGlyph = glyph
        var position = CGPoint(x: Double(box.drawX), y: Double(box.drawY))
        CTFontDrawGlyphs(ctFont, &mutableGlyph, &position, 1, context)
        guard let data = context.data else { return nil }
        let bytesPerRow = context.bytesPerRow
        var coverage = [UInt8](repeating: 0, count: box.width * box.height)
        // CG bitmap memory row 0 is the image top -> copy directly, no flip.
        for row in 0 ..< box.height {
            let source = data.advanced(by: row * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for col in 0 ..< box.width {
                coverage[row * box.width + col] = source[col]
            }
        }
        return coverage
    }

    /// Shelf-packs a cell, blitting its coverage into the atlas. nil when the
    /// atlas is full (glyph dropped rather than overrunning).
    private func pack(cellWidth: Int, cellHeight: Int, coverage: [UInt8]) -> (x: Int, y: Int)? {
        if shelfX + cellWidth > width {
            shelfY += shelfHeight + Self.padding
            shelfX = 0
            shelfHeight = 0
        }
        guard shelfX + cellWidth <= width, shelfY + cellHeight <= height else {
            return nil
        }
        let originX = shelfX
        let originY = shelfY
        for row in 0 ..< cellHeight {
            let destRow = (originY + row) * width + originX
            for col in 0 ..< cellWidth {
                pixels[destRow + col] = coverage[row * cellWidth + col]
            }
        }
        shelfX += cellWidth + Self.padding
        shelfHeight = max(shelfHeight, cellHeight)
        revision += 1
        return (originX, originY)
    }
}
