// Converts a decoded SWF glyph (a list of absolute-twip shape segments in the
// font's glyph-coordinate space) into a CoreGraphics CGPath ready to rasterize
// into the UI glyph atlas. SWF glyph shapes use straight edges and quadratic
// Bezier curves (spec chapter 6); the path fills even-odd per SWF glyph
// semantics (spec chapter 10, "The glyph coordinate system").
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 10
// (pp. 176-179). Documented in docs/formats/swf.md and docs/rendering/ui.md.

import CoreGraphics

nonisolated enum SWFGlyphPath {
    /// Builds a CGPath for a glyph's segments, scaled so one EM square spans
    /// `emPixelSize` pixels, and flipped from SWF's y-down glyph space to
    /// CoreGraphics y-up with the baseline at y = 0. Returns nil for an empty
    /// glyph (no segments or a degenerate path), which draws no quad.
    ///
    /// - Parameters:
    ///   - segments: glyph shape edges in absolute glyph-coordinate twips.
    ///   - unitsPerEM: glyph units per EM (1024 DefineFont2, 20480 DefineFont3).
    ///   - emPixelSize: target EM size in pixels (the text height in pixels).
    static func makePath(
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
