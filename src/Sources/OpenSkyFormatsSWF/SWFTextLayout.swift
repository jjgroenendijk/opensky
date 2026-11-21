// Twip-space glyph layout. DefineText uses its explicit pen offsets; edit text
// lays out from font metrics, with optional wrap and alignment. The output does
// not depend on the viewport. Advances are in glyph units, scaled by
// `textHeightTwips / unitsPerEM`. See docs/formats/swf-text.md.

import Foundation

/// One glyph to draw: the glyph-table index plus the baseline pen position in
/// the text's local twip space.
nonisolated public struct SWFGlyphPlacement: Equatable, Sendable {
    public let glyphIndex: Int
    public let x: Float
    public let y: Float
}

/// A run of glyphs sharing one font, size, and color — one renderer draw.
nonisolated public struct SWFTextRun: Equatable, Sendable {
    /// Font id for static-text records (resolved against the movie's
    /// dictionary); nil for edit text, whose font the caller resolved already.
    public let fontID: UInt16?
    /// Text height (EM size) in twips.
    public let emTwips: Float
    /// Straight text color.
    public let color: SWFColor
    public let glyphs: [SWFGlyphPlacement]
    /// The `<font face>` this run draws in, when the caller resolved it; nil is the field's font.
    public var face: String?
}

nonisolated public struct SWFTextLayoutResult: Equatable, Sendable {
    public let runs: [SWFTextRun]
    /// Characters with no glyph in the font (skipped, never fatal).
    public let missingGlyphs: Int
    /// Lines after wrapping, and how many of them fit the field from the first shown one.
    public var lineCount = 0
    public var visibleLineCount = 0
    /// Set when a line shows only in part: the field's bottom edge, in text-local twips,
    /// where the renderer cuts the glyphs.
    public var clipBottom: Float?
    /// The `<img>` pictures of an HTML field, placed in their lines.
    public var images: [SWFInlineImagePlacement] = []
    /// Every line's first character index, from the first line, in UTF-16 units.
    public var lineStarts: [Int] = []
    /// Twips from one line's top to the next, and from a line's top to its bottom.
    public var lineAdvance: Float = 0
    public var lineHeight: Float = 0
    /// Twips from a line's top to its baseline.
    public var ascent: Float = 0
    /// Each drawn character's box, from the first line, when the caller asked for them.
    public var characterBoxes: [SWFCharacterBox] = []
}

/// One character's box in a laid-out field: its line, and its left edge and width in twips
/// from the field's left edge.
nonisolated public struct SWFCharacterBox: Equatable, Sendable {
    public let character: Int
    public let line: Int
    public let x: Float
    public let width: Float
}

nonisolated public enum SWFTextLayout: Sendable {
    /// The glyphs of one style span, nil for the field's own style.
    private typealias SpanGlyphs = (span: Int?, glyphs: [SWFGlyphPlacement])

    static let twipsPerPixel: Float = 20

    /// Lays out a DefineText/DefineText2 block. Record state (font, height,
    /// color, pen offsets) inherits from earlier records; glyph advances move
    /// the pen. Positions are in the text tag's local space (its MATRIX is
    /// applied by the scene, not here).
    public static func staticText(_ text: SWFTextDefinition) -> SWFTextLayoutResult {
        var runs: [SWFTextRun] = []
        var fontID: UInt16?
        var emTwips: Float = 240
        var color = SWFColor(red: 0, green: 0, blue: 0, alpha: 255)
        var penX: Float = 0
        var penY: Float = 0
        for record in text.records {
            if let recordFont = record.fontID {
                fontID = recordFont
            }
            if let height = record.textHeight {
                emTwips = Float(height)
            }
            if let recordColor = record.color {
                color = recordColor
            }
            if let xOffset = record.xOffset {
                penX = Float(xOffset)
            }
            if let yOffset = record.yOffset {
                penY = Float(yOffset)
            }
            var glyphs: [SWFGlyphPlacement] = []
            glyphs.reserveCapacity(record.glyphs.count)
            for entry in record.glyphs {
                glyphs.append(SWFGlyphPlacement(glyphIndex: entry.glyphIndex, x: penX, y: penY))
                penX += Float(entry.advance)
            }
            if !glyphs.isEmpty {
                runs.append(SWFTextRun(
                    fontID: fontID, emTwips: emTwips, color: color, glyphs: glyphs
                ))
            }
        }
        return SWFTextLayoutResult(runs: runs, missingGlyphs: 0)
    }

    /// Lays out an edit text with the resolved font. A non-nil `content`
    /// replaces `InitialText`, for text set by ActionScript. Alignment comes
    /// from the layout block; justify falls back to left. A non-nil `firstLine`
    /// draws from that zero-based line and only the lines that fit the bounds.
    public static func editText(
        _ text: SWFEditText,
        font: SWFFontDefinition,
        content override: String? = nil,
        firstLine: Int? = nil,
        images: [SWFInlineImage] = [],
        styles: SWFTextStyles = .none,
        fonts: (String) -> SWFFontDefinition? = { _ in nil },
        measuresCharacters: Bool = false
    ) -> SWFTextLayoutResult {
        let content = override ?? text.plainText
        guard let content, !content.isEmpty, !font.glyphs.isEmpty else {
            return SWFTextLayoutResult(runs: [], missingGlyphs: 0)
        }
        let authored = override == nil ? text.htmlContent : nil
        let styles = authored?.styles ?? styles
        let images = authored?.images ?? images
        let metrics = FontScaledMetrics(
            font: font, emTwips: Float(text.fontHeight ?? 240)
        )
        let faces = styles.spans.map { span in
            span.face.flatMap { face in fonts(face).map { (face, $0) } }
        }
        let spanMetrics = zip(styles.spans, faces).map { span, face in
            FontScaledMetrics(font: face?.1 ?? font, emTwips: span.sizeTwips ?? metrics.emTwips)
        }
        var shaper = LineShaper(
            metrics: metrics, images: images, styles: styles, spanMetrics: spanMetrics
        )
        let lines = shapeLines(content, text: text, shaper: &shaper)
        var shown = lines[...]
        var drawn = lines[...]
        var clipBottom: Float?
        if let firstLine {
            let fitting = fittingLineCount(text: text, metrics: metrics)
            let start = min(max(0, firstLine), max(0, lines.count - 1))
            shown = lines[start ..< min(lines.count, start + fitting)]
            drawn = shown
            // Flash draws the next line too when its top is inside the field, cut by
            // the bottom edge. It does not count as a shown line for scrolling.
            let top = Float(text.bounds.yMin) + Float(fitting) * lineAdvance(text, metrics)
            if shown.endIndex < lines.count, top < Float(text.bounds.yMax) {
                drawn = lines[start ..< shown.endIndex + 1]
                clipBottom = Float(text.bounds.yMax)
            }
        }
        let placed = place(lines: Array(drawn), text: text, shaper: shaper)
        let color = text.color ?? SWFColor(red: 0, green: 0, blue: 0, alpha: 255)
        let runs = placed.glyphs.map { span, glyphs in
            SWFTextRun(
                fontID: nil, emTwips: span.map { spanMetrics[$0].emTwips } ?? metrics.emTwips,
                color: span.flatMap { styles.spans[$0].color } ?? color, glyphs: glyphs,
                face: span.flatMap { faces[$0]?.0 }
            )
        }
        var result = SWFTextLayoutResult(runs: runs, missingGlyphs: shaper.missingGlyphs)
        result.lineCount = lines.count
        result.visibleLineCount = shown.count
        result.clipBottom = clipBottom
        result.images = placed.images
        result.lineStarts = lines.map(\.start)
        result.lineAdvance = lineAdvance(text, metrics)
        result.lineHeight = metrics.ascent + metrics.descent
        result.ascent = metrics.ascent
        if measuresCharacters {
            result.characterBoxes = characterBoxes(lines: lines, text: text, styles: styles)
        }
        return result
    }

    /// One shaped line per paragraph, or more when the field wraps.
    private static func shapeLines(
        _ content: String, text: SWFEditText, shaper: inout LineShaper
    ) -> [ShapedLine] {
        let availableWidth = text.availableWidth
        let paragraphs = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        var lines: [ShapedLine] = []
        var paragraphStart = 0
        for (index, paragraph) in paragraphs.enumerated() {
            var shaped = shaper.shape(String(paragraph), start: paragraphStart)
            shaped.paragraph = index
            paragraphStart += paragraph.utf16.count + 1
            if text.flags.wordWrap, availableWidth > 0 {
                lines.append(contentsOf: shaper.wrap(shaped, width: availableWidth))
            } else {
                lines.append(shaped)
            }
        }
        return lines
    }

    private static func lineAdvance(_ text: SWFEditText, _ metrics: FontScaledMetrics) -> Float {
        metrics.ascent + metrics.descent + metrics.leading + Float(text.layout?.leading ?? 0)
    }

    /// Whole lines whose descent stays inside the bounds, at least one. The scroll
    /// properties count these; a line the bottom edge cuts is drawn but not counted.
    private static func fittingLineCount(text: SWFEditText, metrics: FontScaledMetrics) -> Int {
        let advance = lineAdvance(text, metrics)
        let room = Float(text.bounds.yMax - text.bounds.yMin) - metrics.ascent - metrics.descent
        guard advance > 0, room > 0 else { return 1 }
        return Int(room / advance) + 1
    }

    /// Where a line starts after the margins and the alignment. A paragraph's `<p align>`
    /// overrides the field's.
    private static func lineStartX(
        _ line: ShapedLine, text: SWFEditText, styles: SWFTextStyles
    ) -> Float {
        let availableWidth = text.availableWidth
        var startX = Float(text.bounds.xMin) + text.leftInset
        guard availableWidth > 0 else { return startX }
        switch styles.alignments[line.paragraph] ?? text.layout?.align ?? 0 {
        case 1: startX += availableWidth - line.width
        case 2: startX += (availableWidth - line.width) / 2
        default: break
        }
        return startX
    }

    private static func characterBoxes(
        lines: [ShapedLine],
        text: SWFEditText,
        styles: SWFTextStyles
    ) -> [SWFCharacterBox] {
        lines.enumerated().flatMap { index, line in
            let startX = lineStartX(line, text: text, styles: styles) - Float(text.bounds.xMin)
            return line.glyphs.map {
                SWFCharacterBox(
                    character: $0.character, line: index, x: startX + $0.x, width: $0.advance
                )
            }
        }
    }

    /// Positions shaped lines inside the field bounds: first baseline sits one
    /// ascent below the top, subsequent lines advance by
    /// ascent + descent + font leading + field leading. Glyphs group by their style span,
    /// in the order each span first draws.
    private static func place(
        lines: [ShapedLine],
        text: SWFEditText,
        shaper: LineShaper
    ) -> (glyphs: [SpanGlyphs], images: [SWFInlineImagePlacement]) {
        let metrics = shaper.metrics, images = shaper.images, styles = shaper.styles
        let advance = lineAdvance(text, metrics)
        var placed: [SpanGlyphs] = []
        var placedImages: [SWFInlineImagePlacement] = []
        var baseline = Float(text.bounds.yMin) + metrics.ascent
        for line in lines {
            let startX = lineStartX(line, text: text, styles: styles)
            for glyph in line.glyphs {
                if let index = glyph.imageIndex {
                    // The picture's bottom sits on the baseline; a negative vspace moves it down.
                    let image = images[index]
                    let top = baseline - (image.height + image.verticalSpace) * twipsPerPixel
                    placedImages.append(SWFInlineImagePlacement(
                        image: image, x: startX + glyph.x, y: top
                    ))
                    continue
                }
                let placement = SWFGlyphPlacement(
                    glyphIndex: glyph.glyphIndex, x: startX + glyph.x, y: baseline
                )
                if let run = placed.firstIndex(where: { $0.span == glyph.span }) {
                    placed[run].glyphs.append(placement)
                } else {
                    placed.append((glyph.span, [placement]))
                }
            }
            baseline += advance
        }
        return (placed, placedImages)
    }
}

/// Vertical/horizontal font metrics scaled from glyph units to twips.
/// Fallback ratios (fractions of the EM square) apply when a font carries no
/// layout block; 96 of vanilla's 97 fonts have one, so they rarely do.
nonisolated private struct FontScaledMetrics {
    private static let fallbackAscentRatio: Float = 0.8
    private static let fallbackDescentRatio: Float = 0.2
    private static let fallbackAdvanceRatio: Float = 0.6

    let font: SWFFontDefinition
    let emTwips: Float
    let scale: Float
    let ascent: Float
    let descent: Float
    let leading: Float

    init(font: SWFFontDefinition, emTwips: Float) {
        self.font = font
        self.emTwips = emTwips
        scale = emTwips / Float(font.unitsPerEM)
        if let layout = font.layout {
            ascent = Float(layout.ascent) * scale
            descent = Float(layout.descent) * scale
            leading = Float(layout.leading) * scale
        } else {
            ascent = emTwips * Self.fallbackAscentRatio
            descent = emTwips * Self.fallbackDescentRatio
            leading = 0
        }
    }

    func advance(ofGlyphAt index: Int) -> Float {
        if let layout = font.layout, index < layout.glyphMetrics.count {
            return Float(layout.glyphMetrics[index].advance) * scale
        }
        return emTwips * Self.fallbackAdvanceRatio
    }

    func kerning(_ first: UInt16, _ second: UInt16) -> Float {
        guard let layout = font.layout else { return 0 }
        let record = layout.kerning.first { $0.code1 == first && $0.code2 == second }
        return Float(record?.adjustment ?? 0) * scale
    }
}

/// One shaped glyph before line placement: pen x within its line plus its own
/// advance (kerning folded into the preceding glyph's effective advance).
nonisolated private struct ShapedGlyph {
    let glyphIndex: Int
    var x: Float
    let advance: Float
    /// Character is breakable whitespace (wrap point).
    let isSpace: Bool
    /// The character's index in the whole text, in UTF-16 units, as ActionScript counts.
    let character: Int
    /// The style span the glyph draws in, nil for the field's own style.
    var span: Int?

    /// An inline image stands in the line as a glyph with a negative index.
    var imageIndex: Int? {
        glyphIndex < 0 ? -1 - glyphIndex : nil
    }
}

nonisolated private struct ShapedLine {
    /// The index of the line's first character, even when the line has no glyph.
    var start: Int
    var paragraph = 0
    var glyphs: [ShapedGlyph] = []

    var width: Float {
        glyphs.last.map { $0.x + $0.advance } ?? 0
    }
}

/// Maps characters to glyph indices and accumulates pen advances + kerning.
nonisolated private struct LineShaper {
    let metrics: FontScaledMetrics
    let images: [SWFInlineImage]
    var styles = SWFTextStyles.none
    /// The metrics of each style span, in span order.
    var spanMetrics: [FontScaledMetrics] = []
    private(set) var missingGlyphs = 0
    private(set) var nextImage = 0

    static let imageScalar = SWFHTMLText.imageMarker.unicodeScalars.first

    /// `start` is the paragraph's first character index in the whole text, in UTF-16 units.
    mutating func shape(_ text: String, start: Int = 0) -> ShapedLine {
        var line = ShapedLine(start: start)
        var penX: Float = 0
        var previousCode: UInt16?
        var previousSpan: Int?
        var character = start
        for scalar in text.unicodeScalars {
            defer { character += scalar.utf16.count }
            let span = styles.spans.isEmpty ? nil : styles.spanIndex(at: character)
            let metrics = span.map { spanMetrics[$0] } ?? metrics
            if span != previousSpan {
                previousCode = nil
                previousSpan = span
            }
            if scalar == Self.imageScalar, nextImage < images.count {
                let advance = images[nextImage].width * SWFTextLayout.twipsPerPixel
                line.glyphs.append(ShapedGlyph(
                    glyphIndex: -1 - nextImage, x: penX, advance: advance, isSpace: false,
                    character: character, span: span
                ))
                nextImage += 1
                penX += advance
                previousCode = nil
                continue
            }
            guard scalar.value <= UInt16.max else {
                missingGlyphs += 1
                continue
            }
            let code = UInt16(scalar.value)
            guard let glyphIndex = metrics.font.glyphIndex(forCode: code) else {
                missingGlyphs += 1
                previousCode = nil
                continue
            }
            if let previous = previousCode {
                penX += metrics.kerning(previous, code)
            }
            let spacing = span.map { styles.spans[$0].letterSpacingTwips } ?? 0
            let advance = metrics.advance(ofGlyphAt: glyphIndex) + spacing
            line.glyphs.append(ShapedGlyph(
                glyphIndex: glyphIndex,
                x: penX,
                advance: advance,
                isSpace: scalar == " " || scalar == "\t",
                character: character,
                span: span
            ))
            penX += advance
            previousCode = code
        }
        return line
    }

    /// Greedy word wrap at breakable whitespace: whole words move to the next
    /// line (with the breaking spaces dropped); a single word wider than the
    /// field keeps its own overflowing line — no mid-word breaking.
    func wrap(_ line: ShapedLine, width: Float) -> [ShapedLine] {
        guard line.width > width, !line.glyphs.isEmpty else { return [line] }
        var lines: [ShapedLine] = []
        var current = ShapedLine(start: line.start, paragraph: line.paragraph)
        for word in words(of: line) {
            let wordWidth = word.last.map { $0.x - (word.first?.x ?? 0) + $0.advance } ?? 0
            if !current.glyphs.isEmpty, current.width + wordWidth > width {
                lines.append(current)
                current = ShapedLine(
                    start: word.first?.character ?? current.start, paragraph: line.paragraph
                )
            }
            let startX = current.width
            let wordStart = word.first?.x ?? 0
            for glyph in word {
                var moved = glyph
                moved.x = startX + glyph.x - wordStart
                current.glyphs.append(moved)
            }
        }
        lines.append(current)
        return lines
    }

    /// Splits a shaped line into words. Inter-word spaces attach to the end
    /// of the preceding word so intra-line spacing survives, while a break
    /// between words naturally drops them (word x-rebasing skips the gap).
    private func words(of line: ShapedLine) -> [[ShapedGlyph]] {
        var result: [[ShapedGlyph]] = []
        var current: [ShapedGlyph] = []
        var seenNonSpace = false
        for glyph in line.glyphs {
            if !glyph.isSpace, seenNonSpace, current.last?.isSpace == true {
                result.append(current)
                current = []
                seenNonSpace = false
            }
            current.append(glyph)
            seenNonSpace = seenNonSpace || !glyph.isSpace
        }
        if !current.isEmpty {
            result.append(current)
        }
        return result
    }
}

nonisolated extension SWFEditText {
    /// The left margin and the first-line indent, in twips.
    fileprivate var leftInset: Float {
        Float(layout.map { Int($0.leftMargin) + Int($0.indent) } ?? 0)
    }

    /// The width between the margins, where lines wrap and align.
    fileprivate var availableWidth: Float {
        Float(bounds.xMax - bounds.xMin) - leftInset - Float(layout?.rightMargin ?? 0)
    }
}
