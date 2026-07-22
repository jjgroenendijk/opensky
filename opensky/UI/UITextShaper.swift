// CoreText shaping + measurement + greedy word wrap for the UI layer
// (M8.1.1). One code path (CTLineCreateWithAttributedString + glyph runs)
// drives measurement (font at point size) and rasterized emission (font at
// pixel size); advances scale linearly with size, so the two stay consistent.

import CoreText
import Foundation

/// One positioned glyph from a shaped line. `x`/`y` are baseline-relative
/// positions in the shaping font's coordinate space.
struct UIShapedGlyph: Equatable {
    let glyphID: CGGlyph
    let x: Float
    let y: Float
}

/// Vertical typographic metrics of a font, in the font's size units.
struct UIFontMetrics {
    let ascent: Float
    let descent: Float
    let leading: Float

    var lineHeight: Float {
        ascent + descent + leading
    }
}

/// A shaped single line: its glyphs plus typographic metrics.
struct UIShapedLine {
    let glyphs: [UIShapedGlyph]
    let width: Float
    let metrics: UIFontMetrics

    var height: Float {
        metrics.lineHeight
    }
}

enum UITextShaper {
    /// Shapes one line with `font` (already at the desired size).
    static func shape(_ text: String, font: CTFont) -> UIShapedLine {
        // kCTFontAttributeName avoids an AppKit/UIKit import for NSAttributedString.Key.font.
        let fontKey = NSAttributedString.Key(kCTFontAttributeName as String)
        let attributed = NSAttributedString(string: text, attributes: [fontKey: font])
        let line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let width = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
        var glyphs: [UIShapedGlyph] = []
        let runs = (CTLineGetGlyphRuns(line) as NSArray) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var ids = [CGGlyph](repeating: 0, count: count)
            var positions = [CGPoint](repeating: .zero, count: count)
            CTRunGetGlyphs(run, CFRangeMake(0, count), &ids)
            CTRunGetPositions(run, CFRangeMake(0, count), &positions)
            for index in 0 ..< count {
                glyphs.append(UIShapedGlyph(
                    glyphID: ids[index],
                    x: Float(positions[index].x),
                    y: Float(positions[index].y)
                ))
            }
        }
        return UIShapedLine(
            glyphs: glyphs,
            width: Float(width),
            metrics: UIFontMetrics(
                ascent: Float(ascent), descent: Float(descent), leading: Float(leading)
            )
        )
    }

    /// Ascent/descent/leading of `font`, independent of any string.
    static func lineMetrics(_ font: CTFont) -> UIFontMetrics {
        UIFontMetrics(
            ascent: Float(CTFontGetAscent(font)),
            descent: Float(CTFontGetDescent(font)),
            leading: Float(CTFontGetLeading(font))
        )
    }

    /// Width + height of `text` on one line at `font.pointSize`, in points.
    static func measure(_ text: String, font: UIFont) -> UISize {
        let line = shape(text, font: font.makeCTFont(size: CGFloat(font.pointSize)))
        return UISize(width: line.width, height: line.height)
    }

    /// Greedy word wrap to `maxWidth` points. Words split on spaces + newlines
    /// (explicit breaks are treated as spaces); a single word wider than the
    /// limit still occupies its own line rather than being dropped.
    static func wrap(_ text: String, font: UIFont, maxWidth: Float) -> [String] {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init)
        guard !words.isEmpty else { return [] }
        let ctFont = font.makeCTFont(size: CGFloat(font.pointSize))
        var lines: [String] = []
        var current = ""
        for word in words {
            let candidate = current.isEmpty ? word : current + " " + word
            if current.isEmpty || shape(candidate, font: ctFont).width <= maxWidth {
                current = candidate
            } else {
                lines.append(current)
                current = word
            }
        }
        if !current.isEmpty {
            lines.append(current)
        }
        return lines
    }
}
