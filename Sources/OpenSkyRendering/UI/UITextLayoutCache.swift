// Fonts, shaped lines and wrapped text kept across frames, so a HUD string that
// stays the same is shaped once. It lives on the glyph atlas and follows its threading.

import CoreText

nonisolated public final class UITextLayoutCache {
    /// Entries each table may hold. A full table is emptied, because the HUD shows
    /// far fewer strings than this, so only a long run of changing text fills it.
    public static let entryLimit = 2048

    /// Lines shaped by CoreText since the cache was made, for tests and readouts.
    public private(set) var shapedLineCount = 0
    private var fonts: [UITextFontKey: CTFont] = [:]
    private var lines: [UITextLineKey: UIShapedLine] = [:]
    private var wraps: [UITextWrapKey: [String]] = [:]

    public init() {}

    /// `font` at `size`, in points for measurement or pixels for rasterising.
    public func ctFont(_ font: UIFont, size: Float) -> CTFont {
        let key = UITextFontKey(weight: font.weight, size: size)
        if let cached = fonts[key] {
            return cached
        }
        let made = font.makeCTFont(size: CGFloat(size))
        Self.store(made, for: key, in: &fonts)
        return made
    }

    public func shape(_ text: String, font: UIFont, size: Float) -> UIShapedLine {
        let key = UITextLineKey(text: text, font: UITextFontKey(weight: font.weight, size: size))
        if let cached = lines[key] {
            return cached
        }
        let shaped = UITextShaper.shape(text, font: ctFont(font, size: size))
        shapedLineCount += 1
        Self.store(shaped, for: key, in: &lines)
        return shaped
    }

    public func wrap(_ text: String, font: UIFont, maxWidth: Float) -> [String] {
        let key = UITextWrapKey(
            text: text,
            font: UITextFontKey(weight: font.weight, size: font.pointSize),
            maxWidth: maxWidth
        )
        if let cached = wraps[key] {
            return cached
        }
        let wrapped = UITextShaper.wrap(text, font: font, maxWidth: maxWidth)
        Self.store(wrapped, for: key, in: &wraps)
        return wrapped
    }

    private static func store<Key, Value>(
        _ value: Value, for key: Key, in table: inout [Key: Value]
    ) {
        if table.count >= entryLimit {
            table.removeAll(keepingCapacity: true)
        }
        table[key] = value
    }
}

nonisolated struct UITextFontKey: Hashable {
    let weight: UIFont.Weight
    let size: Float
}

nonisolated struct UITextLineKey: Hashable {
    let text: String
    let font: UITextFontKey
}

nonisolated struct UITextWrapKey: Hashable {
    let text: String
    let font: UITextFontKey
    let maxWidth: Float
}
