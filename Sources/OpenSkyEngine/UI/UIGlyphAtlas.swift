// CPU shelf-packed single-channel glyph atlas (M8.1.1). Rasterizes glyphs via
// CoreGraphics into an r8 coverage bitmap the renderer uploads to an r8Unorm
// texture. A reserved solid-white texel backs untextured quads so one pipeline
// draws fills + text. Font smoothing is disabled -> same-process renders are
// byte-deterministic. Glyph cache keyed by font + glyph id + pixel size.
//
// The atlas is fixed-size, so a host that swaps content (the UI Lab movie
// selector, later real menus) has to hand cells back or the shelf runs out and
// later text silently disappears (issue #127). Every packed cell therefore
// keeps its coverage bytes, and `releaseSWFGlyphs(where:)` drops a released
// movie's glyphs and repacks the survivors. The packing + eviction half of the
// class lives in UIGlyphAtlasPacking.swift.

import CoreGraphics
import CoreText
import simd

/// Cache key: glyph source namespace + font discriminator + glyph id + integer
/// pixel size. The namespace keeps SWF-font glyphs from colliding with system
/// glyphs that happen to share the same numeric `fontKey`.
nonisolated public struct UIGlyphKey: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case system
        case swf
    }

    public let source: Source
    public let fontKey: Int
    public let glyphID: UInt16
    public let pixelSize: Int
}

/// A packed glyph's atlas placement + placement metrics, all in pixels.
nonisolated public struct UIGlyphEntry: Equatable, Sendable {
    /// Atlas UV of the coverage cell (top-left, bottom-right), normalized.
    public let uvMin: SIMD2<Float>
    public let uvMax: SIMD2<Float>
    /// Coverage cell pixel size.
    public let size: SIMD2<Float>
    /// x: left side bearing; y: height of the cell above the baseline.
    public let bearing: SIMD2<Float>

    public static let empty = UIGlyphEntry(uvMin: .zero, uvMax: .zero, size: .zero, bearing: .zero)

    /// Whitespace / zero-area glyph -> emits no quad.
    public var isEmpty: Bool {
        size.x <= 0 || size.y <= 0
    }
}

nonisolated public final class UIGlyphAtlas {
    public static let dimension = 512
    public static let padding = 1
    public static let whiteBlock = 4

    /// A cached glyph: its placement plus the coverage bytes that produced it.
    /// Coverage is retained so an eviction can repack the survivors without
    /// re-rasterizing them; empty (whitespace, unpackable) glyphs carry none.
    public struct PackedGlyph: Sendable {
        public let entry: UIGlyphEntry
        public let coverage: [UInt8]?

        public static let empty = PackedGlyph(entry: .empty, coverage: nil)
    }

    public let width = dimension
    public let height = dimension
    /// Coverage bytes, row-major, top-left origin (matches Metal texture v-down).
    /// Only the packing extension writes it.
    public private(set) var pixels: [UInt8]
    /// Bumped whenever the atlas image changes — new glyphs packed, or survivors
    /// repacked by an eviction -> the renderer re-uploads the texture.
    public var revision = 0
    /// UV of a fully-opaque texel; solid fills sample it for coverage == 1.
    public let whiteUV: SIMD2<Float>
    /// Glyphs dropped because the atlas was full, counted since the last
    /// eviction. Non-zero means text is missing from the rendered frame.
    public var packFailures = 0
    /// Atlas texels occupied by packed glyph cells (the white block excluded).
    public var usedTexels = 0

    /// Internal, not private: the packing extension lives in another file so
    /// this type stays inside the strict-lint type-body limit.
    public var cache: [UIGlyphKey: PackedGlyph] = [:]
    public var shelfX = 0
    public var shelfY: Int
    public var shelfHeight = 0

    public init() {
        pixels = [UInt8](repeating: 0, count: Self.dimension * Self.dimension)
        whiteUV = SIMD2(
            Float(Self.whiteBlock) / 2 / Float(Self.dimension),
            Float(Self.whiteBlock) / 2 / Float(Self.dimension)
        )
        shelfY = Self.whiteBlock + Self.padding
        clearImage()
    }

    /// Glyph cells currently occupying the atlas (empty glyphs excluded).
    public var packedGlyphCount: Int {
        cache.values.count { $0.coverage != nil }
    }

    /// Occupied fraction of the atlas, 0...1, for diagnostics readouts.
    public var occupancy: Float {
        Float(usedTexels) / Float(width * height)
    }

    /// Returns the cached entry for a system-font glyph, rasterizing + packing
    /// on first use. `ctFont` must be built at `pixelSize` (same font `fontKey`
    /// identifies).
    public func entry(
        fontKey: Int,
        glyphID: CGGlyph,
        pixelSize: Int,
        ctFont: CTFont
    ) -> UIGlyphEntry {
        let key = UIGlyphKey(
            source: .system, fontKey: fontKey, glyphID: UInt16(glyphID), pixelSize: pixelSize
        )
        if let cached = cache[key] {
            return cached.entry
        }
        var glyph = glyphID
        let bounds = CTFontGetBoundingRectsForGlyphs(ctFont, .default, &glyph, nil, 1)
        let packed = rasterize(bounds: bounds) { context, box in
            var mutableGlyph = glyph
            var position = CGPoint(x: Double(box.drawX), y: Double(box.drawY))
            CTFontDrawGlyphs(ctFont, &mutableGlyph, &position, 1, context)
        }
        cache[key] = packed
        return packed.entry
    }

    /// Returns the cached entry for an SWF-font glyph, rasterizing the supplied
    /// pixel-space CGPath (y-up, baseline at the origin) with an even-odd fill
    /// on first use. `makePath` runs only on a cache miss; nil (an empty glyph)
    /// caches as `.empty`. `fontKey` must be unique per (movie, font id) so two
    /// fonts' glyph indices never collide; the `.swf` namespace already
    /// separates these from system glyphs.
    public func swfEntry(
        fontKey: Int,
        glyphIndex: Int,
        emPixelSize: Int,
        makePath: () -> CGPath?
    ) -> UIGlyphEntry {
        let key = UIGlyphKey(
            source: .swf, fontKey: fontKey,
            glyphID: UInt16(truncatingIfNeeded: glyphIndex), pixelSize: emPixelSize
        )
        if let cached = cache[key] {
            return cached.entry
        }
        let packed: PackedGlyph = if let path = makePath() {
            rasterize(bounds: path.boundingBoxOfPath) { context, box in
                context.translateBy(x: CGFloat(box.drawX), y: CGFloat(box.drawY))
                context.addPath(path)
                context.drawPath(using: .eoFill)
            }
        } else {
            .empty
        }
        cache[key] = packed
        return packed.entry
    }

    /// Clears the image to its initial state: everything transparent except the
    /// reserved solid-white block top-left that backs untextured quads.
    public func clearImage() {
        for index in pixels.indices {
            pixels[index] = 0
        }
        for row in 0 ..< Self.whiteBlock {
            for col in 0 ..< Self.whiteBlock {
                pixels[row * Self.dimension + col] = 255
            }
        }
    }

    /// Writes one packed cell's coverage into the atlas image.
    public func blit(
        coverage: [UInt8],
        cellWidth: Int,
        cellHeight: Int,
        originX: Int,
        originY: Int
    ) {
        for row in 0 ..< cellHeight {
            let destRow = (originY + row) * width + originX
            for col in 0 ..< cellWidth {
                pixels[destRow + col] = coverage[row * cellWidth + col]
            }
        }
    }
}
