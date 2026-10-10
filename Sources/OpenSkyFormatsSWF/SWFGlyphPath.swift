// Converts a decoded glyph into a CGPath for the UI glyph atlas. Glyphs use
// straight and quadratic edges and fill even-odd. Spec: SWF v19 chapters 6 and
// 10. See docs/formats/swf-text.md and docs/rendering/ui.md.

import CoreGraphics

nonisolated public enum SWFGlyphPath: Sendable {
    /// A CGPath for a glyph, scaled so one EM spans `emPixelSize` pixels and
    /// flipped to y-up with the baseline at 0. `unitsPerEM` is 1024 for
    /// DefineFont2 and 20480 for DefineFont3. Nil for an empty glyph.
    public static func makePath(
        segments: [SWFShapeSegment],
        unitsPerEM: Int,
        emPixelSize: Int
    ) -> CGPath? {
        guard !segments.isEmpty, unitsPerEM > 0, emPixelSize > 0 else { return nil }
        let scale = CGFloat(emPixelSize) / CGFloat(unitsPerEM)
        let path = CGMutablePath()
        // NaN start guarantees the first segment opens a new contour, and any
        // move-to (a glyph's fromPoint jumping off the previous end) starts one.
        var pen = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
        for segment in segments {
            let from = point(segment.fromX, segment.fromY, scale: scale)
            if from != pen {
                path.move(to: from)
            }
            switch segment.edge {
            case let .line(toX, toY):
                let end = point(toX, toY, scale: scale)
                path.addLine(to: end)
                pen = end
            case let .quadratic(controlX, controlY, toX, toY):
                let control = point(controlX, controlY, scale: scale)
                let end = point(toX, toY, scale: scale)
                path.addQuadCurve(to: end, control: control)
                pen = end
            }
        }
        return path.isEmpty ? nil : path
    }

    /// Maps a glyph-space point (y-down twips) to scaled CoreGraphics y-up space.
    private static func point(_ x: Int32, _ y: Int32, scale: CGFloat) -> CGPoint {
        CGPoint(x: CGFloat(x) * scale, y: CGFloat(-y) * scale)
    }
}
