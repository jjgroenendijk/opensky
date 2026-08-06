// Rasterization, shelf packing, and eviction for UIGlyphAtlas (issue #127).
// Split out of UIGlyphAtlas.swift so the class body stays inside the strict-lint
// type-body limit.
//
// Eviction exists because the atlas is one fixed-size texture shared by every
// movie: a host that swaps SWF movies (the UI Lab selector, later real menus)
// otherwise accumulates cells for fonts nothing draws any more, and the shelf
// runs out mid-sweep — later movies then render with no text at all. Releasing
// a movie drops its glyphs and repacks the survivors, which is exact because
// every packed cell keeps the coverage bytes it was rasterized from.

import CoreGraphics
import simd

nonisolated extension UIGlyphAtlas {
    /// A glyph's tight coverage cell: pixel size + the draw origin (offset that
    /// shifts the baseline-relative bbox into the cell) + the left/top bearings.
    struct GlyphBox {
        let width: Int
        let height: Int
        let drawX: Int
        let drawY: Int
        let bearingX: Int
        let bearingY: Int
    }

    /// Drops every SWF glyph whose `fontKey` satisfies `isReleased` and repacks
    /// the survivors from their retained coverage, reclaiming the freed cells.
    /// System-font glyphs are never released — they belong to the dev UI, which
    /// outlives any movie. Returns the number of glyph cells dropped.
    ///
    /// Callers must not hold `UIGlyphEntry` values across this call: survivors
    /// keep their metrics but move, so their UVs change. Consumers re-query per
    /// frame, and the bumped `revision` re-uploads the texture.
    @discardableResult
    func releaseSWFGlyphs(where isReleased: (Int) -> Bool) -> Int {
        let released = cache.filter { key, _ in
            key.source == .swf && isReleased(key.fontKey)
        }
        guard !released.isEmpty else { return 0 }
        let droppedCells = released.values.count { $0.coverage != nil }
        for key in released.keys {
            cache.removeValue(forKey: key)
        }
        repackSurvivors()
        return droppedCells
    }

    /// Rebuilds the atlas image from the surviving cache entries, tallest cell
    /// first so the shelves stay tight. Deterministic: the survivor order is a
    /// total order over the keys, so the same survivor set always produces the
    /// same image. A survivor that somehow fails to repack is evicted rather
    /// than left pointing at a stale cell.
    private func repackSurvivors() {
        let survivors = cache
            .filter { $0.value.coverage != nil }
            .sorted { Self.packsBefore($0, $1) }
        clearImage()
        shelfX = 0
        shelfY = Self.whiteBlock + Self.padding
        shelfHeight = 0
        usedTexels = 0
        packFailures = 0
        for (key, glyph) in survivors {
            guard let coverage = glyph.coverage else { continue }
            let cellWidth = Int(glyph.entry.size.x)
            let cellHeight = Int(glyph.entry.size.y)
            guard
                let placement = pack(
                    cellWidth: cellWidth, cellHeight: cellHeight, coverage: coverage
                )
            else {
                cache.removeValue(forKey: key)
                continue
            }
            cache[key] = PackedGlyph(
                entry: UIGlyphEntry(
                    uvMin: uv(x: placement.x, y: placement.y),
                    uvMax: uv(x: placement.x + cellWidth, y: placement.y + cellHeight),
                    size: glyph.entry.size,
                    bearing: glyph.entry.bearing
                ),
                coverage: coverage
            )
        }
        revision += 1
    }

    /// Repack order: tallest cell first, ties broken by a total order over the
    /// key fields so repacking never depends on dictionary iteration order.
    private static func packsBefore(
        _ lhs: (key: UIGlyphKey, value: PackedGlyph),
        _ rhs: (key: UIGlyphKey, value: PackedGlyph)
    ) -> Bool {
        if lhs.value.entry.size.y != rhs.value.entry.size.y {
            return lhs.value.entry.size.y > rhs.value.entry.size.y
        }
        if lhs.key.fontKey != rhs.key.fontKey {
            return lhs.key.fontKey < rhs.key.fontKey
        }
        if lhs.key.glyphID != rhs.key.glyphID {
            return lhs.key.glyphID < rhs.key.glyphID
        }
        if lhs.key.pixelSize != rhs.key.pixelSize {
            return lhs.key.pixelSize < rhs.key.pixelSize
        }
        return lhs.key.source == .system && rhs.key.source == .swf
    }

    private func uv(x: Int, y: Int) -> SIMD2<Float> {
        SIMD2(Float(x) / Float(width), Float(y) / Float(height))
    }

    /// Shared rasterization: fit a tight cell to `bounds`, run `draw` into a
    /// grayscale context, and shelf-pack the coverage. `draw` positions its
    /// content using the box's draw origin (system glyphs via the draw
    /// position, SWF paths via a context translate).
    func rasterize(
        bounds: CGRect,
        draw: (CGContext, GlyphBox) -> Void
    ) -> PackedGlyph {
        guard
            let box = glyphBox(from: bounds),
            let coverage = renderCoverage(box: box, draw: draw)
        else { return .empty }
        guard
            let placement = pack(cellWidth: box.width, cellHeight: box.height, coverage: coverage)
        else {
            packFailures += 1
            return .empty
        }
        return PackedGlyph(
            entry: UIGlyphEntry(
                uvMin: uv(x: placement.x, y: placement.y),
                uvMax: uv(x: placement.x + box.width, y: placement.y + box.height),
                size: SIMD2(Float(box.width), Float(box.height)),
                bearing: SIMD2(Float(box.bearingX), Float(box.bearingY))
            ),
            coverage: coverage
        )
    }

    /// A padded integer cell around a baseline-relative bounding box. `maxY` is
    /// the cell top's height above the baseline (CG y-up). nil for an empty box.
    private func glyphBox(from bounds: CGRect) -> GlyphBox? {
        guard bounds.width > 0, bounds.height > 0, !bounds.isNull, !bounds.isInfinite else {
            return nil
        }
        let minX = Int(bounds.minX.rounded(.down)) - Self.padding
        let minY = Int(bounds.minY.rounded(.down)) - Self.padding
        let maxX = Int(bounds.maxX.rounded(.up)) + Self.padding
        let maxY = Int(bounds.maxY.rounded(.up)) + Self.padding
        let box = GlyphBox(
            width: maxX - minX, height: maxY - minY,
            drawX: -minX, drawY: -minY, bearingX: minX, bearingY: maxY
        )
        guard box.width > 0, box.height > 0 else { return nil }
        return box
    }

    /// Draws white-on-black into a tight grayscale bitmap, returning its
    /// coverage bytes (top-left origin). Font smoothing off for determinism.
    private func renderCoverage(box: GlyphBox, draw: (CGContext, GlyphBox) -> Void) -> [UInt8]? {
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
        draw(context, box)
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
        blit(
            coverage: coverage, cellWidth: cellWidth, cellHeight: cellHeight,
            originX: originX, originY: originY
        )
        shelfX += cellWidth + Self.padding
        shelfHeight = max(shelfHeight, cellHeight)
        usedTexels += cellWidth * cellHeight
        revision += 1
        return (originX, originY)
    }
}
