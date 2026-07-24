// Twip-space glyph layout for the display-list renderer: DefineText records
// place glyphs from their explicit pen offsets and advances; DefineEditText
// initial content lays out line by line from the resolved font's metrics
// (advance table, kerning, ascent/descent) with optional word wrap and
// paragraph alignment. Output is viewport-independent — the renderer scales
// placements by the concatenated transform — so wrap and alignment are
// deterministic per movie.
//
// Reference: Adobe SWF File Format Specification, version 19, chapter 10 —
// TEXTRECORD/GLYPHENTRY (pp. 174-175), DefineEditText layout fields (p. 177),
// DefineFont2/3 layout metrics (pp. 178-180). Glyph advances and kerning are
// in glyph units (EM = `unitsPerEM`), scaled by `textHeightTwips / unitsPerEM`.

import Foundation

/// One glyph to draw: the glyph-table index plus the baseline pen position in
/// the text's local twip space.
nonisolated struct SWFGlyphPlacement: Equatable {
    let glyphIndex: Int
    let x: Float
    let y: Float
}

/// A run of glyphs sharing one font, size, and color — one renderer draw.
nonisolated struct SWFTextRun: Equatable {
    /// Font id for static-text records (resolved against the movie's
    /// dictionary); nil for edit text, whose font the caller resolved already.
    let fontID: UInt16?
    /// Text height (EM size) in twips.
    let emTwips: Float
    /// Straight text color.
    let color: SWFColor
    let glyphs: [SWFGlyphPlacement]
}

nonisolated struct SWFTextLayoutResult: Equatable {
    let runs: [SWFTextRun]
    /// Characters with no glyph in the font (skipped, never fatal).
    let missingGlyphs: Int
}

nonisolated enum SWFTextLayout {
    /// Lays out a DefineText/DefineText2 block. Record state (font, height,
    /// color, pen offsets) inherits from earlier records; glyph advances move
    /// the pen. Positions are in the text tag's local space (its MATRIX is
    /// applied by the scene, not here).
    static func staticText(_ text: SWFTextDefinition) -> SWFTextLayoutResult {
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

    /// Lays out an edit text's plain initial content with the resolved font.
    /// Lines split on newlines; word wrap applies when the field is flagged
    /// WordWrap; alignment comes from the layout block (0 left, 1 right,
    /// 2 center; justify falls back to left).
    static func editText(
        _ text: SWFEditText,
        font: SWFFontDefinition
    ) -> SWFTextLayoutResult {
        guard let content = text.plainText, !content.isEmpty, !font.glyphs.isEmpty else {
            return SWFTextLayoutResult(runs: [], missingGlyphs: 0)
        }
        let metrics = FontScaledMetrics(
            font: font, emTwips: Float(text.fontHeight ?? 240)
        )
        let leftInset = Float(text.layout.map { Int($0.leftMargin) + Int($0.indent) } ?? 0)
        let rightInset = Float(text.layout?.rightMargin ?? 0)
        let availableWidth = Float(text.bounds.xMax - text.bounds.xMin) - leftInset - rightInset
        var shaper = LineShaper(metrics: metrics)
        let paragraphs = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
        var lines: [ShapedLine] = []
        for paragraph in paragraphs {
            let shaped = shaper.shape(String(paragraph))
            if text.flags.wordWrap, availableWidth > 0 {
                lines.append(contentsOf: shaper.wrap(shaped, width: availableWidth))
            } else {
                lines.append(shaped)
            }
        }
        let placed = place(
            lines: lines, text: text, metrics: metrics,
            leftInset: leftInset, availableWidth: availableWidth
        )
        let color = text.color ?? SWFColor(red: 0, green: 0, blue: 0, alpha: 255)
        let runs = placed.isEmpty ? [] : [SWFTextRun(
            fontID: nil, emTwips: metrics.emTwips, color: color, glyphs: placed
        )]
        return SWFTextLayoutResult(runs: runs, missingGlyphs: shaper.missingGlyphs)
    }

    /// Positions shaped lines inside the field bounds: first baseline sits one
    /// ascent below the top, subsequent lines advance by
    /// ascent + descent + font leading + field leading.
    private static func place(
        lines: [ShapedLine],
        text: SWFEditText,
        metrics: FontScaledMetrics,
        leftInset: Float,
        availableWidth: Float
    ) -> [SWFGlyphPlacement] {
        let align = text.layout?.align ?? 0
        let extraLeading = Float(text.layout?.leading ?? 0)
        let lineAdvance = metrics.ascent + metrics.descent + metrics.leading + extraLeading
        var placed: [SWFGlyphPlacement] = []
        var baseline = Float(text.bounds.yMin) + metrics.ascent
        for line in lines {
            var startX = Float(text.bounds.xMin) + leftInset
            if availableWidth > 0 {
                switch align {
                case 1: startX += availableWidth - line.width
                case 2: startX += (availableWidth - line.width) / 2
                default: break
                }
            }
            for glyph in line.glyphs {
                placed.append(SWFGlyphPlacement(
                    glyphIndex: glyph.glyphIndex, x: startX + glyph.x, y: baseline
                ))
            }
            baseline += lineAdvance
        }
        return placed
    }
}

/// Vertical/horizontal font metrics scaled from glyph units to twips.
/// Fallback ratios (fractions of the EM square) apply when a font carries no
/// layout block; 96 of vanilla's 97 fonts have one, so they rarely do.
private struct FontScaledMetrics {
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
private struct ShapedGlyph {
    let glyphIndex: Int
    var x: Float
    let advance: Float
    /// Character is breakable whitespace (wrap point).
    let isSpace: Bool
}

private struct ShapedLine {
    var glyphs: [ShapedGlyph] = []

    var width: Float {
        glyphs.last.map { $0.x + $0.advance } ?? 0
    }
}

/// Maps characters to glyph indices and accumulates pen advances + kerning.
private struct LineShaper {
    let metrics: FontScaledMetrics
    private(set) var missingGlyphs = 0

    mutating func shape(_ text: String) -> ShapedLine {
        var line = ShapedLine()
        var penX: Float = 0
        var previousCode: UInt16?
        for scalar in text.unicodeScalars {
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
            let advance = metrics.advance(ofGlyphAt: glyphIndex)
            line.glyphs.append(ShapedGlyph(
                glyphIndex: glyphIndex,
                x: penX,
                advance: advance,
                isSpace: scalar == " " || scalar == "\t"
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
        var current = ShapedLine()
        for word in words(of: line) {
            let wordWidth = word.last.map { $0.x - (word.first?.x ?? 0) + $0.advance } ?? 0
            if !current.glyphs.isEmpty, current.width + wordWidth > width {
                lines.append(current)
                current = ShapedLine()
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
