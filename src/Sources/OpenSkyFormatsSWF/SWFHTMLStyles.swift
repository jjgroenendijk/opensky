// The styles of an HTML text: `<font>` colour, size, face, and letter spacing, `<p align>`,
// paragraph and line breaks, and character entities. See docs/formats/swf-text.md#html-text.

import Foundation

/// A style that holds from `start`, a UTF-16 offset into the plain text, to the next span.
/// A nil member keeps the field's own value.
nonisolated public struct SWFTextStyleSpan: Equatable, Sendable {
    public var start: Int
    public var color: SWFColor?
    public var sizeTwips: Float?
    public var face: String?
    public var letterSpacingTwips: Float = 0

    public init(
        start: Int, color: SWFColor? = nil, sizeTwips: Float? = nil, face: String? = nil,
        letterSpacingTwips: Float = 0
    ) {
        self.start = start
        self.color = color
        self.sizeTwips = sizeTwips
        self.face = face
        self.letterSpacingTwips = letterSpacingTwips
    }

    func restarted(at offset: Int) -> SWFTextStyleSpan {
        var copy = self
        copy.start = offset
        return copy
    }
}

/// The spans of a text in order, and each paragraph's alignment that `<p align>` set,
/// with the DefineEditText codes: 0 left, 1 right, 2 centre, 3 justify.
nonisolated public struct SWFTextStyles: Equatable, Sendable {
    public var spans: [SWFTextStyleSpan] = []
    public var alignments: [Int: UInt8] = [:]

    public static let none = SWFTextStyles()

    public init(spans: [SWFTextStyleSpan] = [], alignments: [Int: UInt8] = [:]) {
        self.spans = spans
        self.alignments = alignments
    }

    /// The index of the span that styles `character`, or nil before the first span.
    func spanIndex(at character: Int) -> Int? {
        spans.lastIndex { $0.start <= character }
    }
}

/// An HTML text taken apart: the plain text, its inline images, and its styles.
nonisolated public struct SWFHTMLContent: Equatable, Sendable {
    public var text = ""
    public var images: [SWFInlineImage] = []
    public var styles = SWFTextStyles()
}

nonisolated extension SWFHTMLText {
    /// Flash ends a paragraph with a carriage return in the plain text.
    static let paragraphEnd: Character = "\r"

    /// Splits `html` into text and styles. `</p>` and `<br>` end a line; the line break
    /// the last `</p>` leaves at the very end is dropped, as Flash's `text` shows it.
    public static func parseStyled(_ html: String) -> SWFHTMLContent {
        var parser = StyledParser()
        var tag: String?
        var entity: String?
        for character in html {
            if var body = tag {
                if character == ">" {
                    parser.apply(tag: body)
                    tag = nil
                } else {
                    body.append(character)
                    tag = body
                }
            } else if var name = entity {
                if character == ";" {
                    parser.append(text: decodedEntity(name) ?? "&\(name);")
                    entity = nil
                } else if name.count < 8, character != "<", character != "&" {
                    name.append(character)
                    entity = name
                } else {
                    parser.append(text: "&" + name)
                    entity = nil
                    parser.append(character: character, tag: &tag, entity: &entity)
                }
            } else {
                parser.append(character: character, tag: &tag, entity: &entity)
            }
        }
        if let entity {
            parser.append(text: "&" + entity)
        }
        return parser.finished()
    }

    static func decodedEntity(_ name: String) -> String? {
        switch name.lowercased() {
        case "amp": return "&"
        case "lt": return "<"
        case "gt": return ">"
        case "quot": return "\""
        case "apos": return "'"
        case "nbsp": return "\u{00A0}"
        default:
            let number = name.hasPrefix("#x") || name.hasPrefix("#X")
                ? UInt32(name.dropFirst(2), radix: 16)
                : name.hasPrefix("#") ? UInt32(name.dropFirst()) : nil
            return number.flatMap(Unicode.Scalar.init).map { String(Character($0)) }
        }
    }

    /// `#RRGGBB` as an opaque colour.
    static func color(_ value: String) -> SWFColor? {
        let digits = value.trimmingCharacters(in: .whitespaces).drop { $0 == "#" }
        guard digits.count == 6, let packed = UInt32(digits, radix: 16) else { return nil }
        return SWFColor(
            red: UInt8(packed >> 16 & 0xFF), green: UInt8(packed >> 8 & 0xFF),
            blue: UInt8(packed & 0xFF), alpha: 255
        )
    }
}

nonisolated extension SWFHTMLText {
    /// The running state of `parseStyled`: the text so far, the `<font>` stack, and the spans.
    private struct StyledParser {
        var content = SWFHTMLContent()
        var fonts: [SWFTextStyleSpan] = []
        var paragraph = 0
        var endsWithParagraph = false

        var offset: Int {
            content.text.utf16.count
        }

        mutating func append(
            character: Character, tag: inout String?, entity: inout String?
        ) {
            switch character {
            case "<": tag = ""
            case "&": entity = ""
            default: append(text: String(character))
            }
        }

        mutating func append(text: String) {
            content.text += text
            endsWithParagraph = false
        }

        mutating func apply(tag body: String) {
            let trimmed = body.trimmingCharacters(in: .whitespaces)
            let name = String(trimmed.lowercased().prefix { !$0.isWhitespace })
            let attributes = SWFHTMLText.attributes(of: String(trimmed.dropFirst(name.count)))
            switch name {
            case "font":
                openFont(attributes)
            case "/font":
                _ = fonts.popLast()
                markStyle(fonts.last ?? SWFTextStyleSpan(start: 0))
            case "p":
                if let align = attributes["align"].flatMap(Self.alignCode) {
                    content.styles.alignments[paragraph] = align
                }
            case "/p", "br", "br/":
                content.text.append(SWFHTMLText.paragraphEnd)
                paragraph += 1
                endsWithParagraph = name == "/p"
            case "img":
                if let image = SWFHTMLText.image(fromTag: trimmed) {
                    append(text: String(SWFHTMLText.imageMarker))
                    content.images.append(image)
                }
            default:
                break
            }
        }

        private mutating func openFont(_ attributes: [String: String]) {
            var style = fonts.last ?? SWFTextStyleSpan(start: 0)
            if let color = attributes["color"].flatMap(SWFHTMLText.color) {
                style.color = color
            }
            if
                let size = attributes["size"]
                    .flatMap({ Float($0.trimmingCharacters(in: .whitespaces)) })
            {
                style.sizeTwips = size * SWFTextLayout.twipsPerPixel
            }
            if let face = attributes["face"], !face.isEmpty {
                style.face = face
            }
            if let spacing = attributes["letterspacing"].flatMap({ Float($0) }) {
                style.letterSpacingTwips = spacing * SWFTextLayout.twipsPerPixel
            }
            fonts.append(style)
            markStyle(style)
        }

        /// Starts `style` at the current offset. A span with no text yet is replaced.
        private mutating func markStyle(_ style: SWFTextStyleSpan) {
            let span = style.restarted(at: offset)
            if content.styles.spans.last?.start == offset {
                content.styles.spans.removeLast()
            }
            let current = content.styles.spans.last ?? SWFTextStyleSpan(start: 0)
            if current.restarted(at: offset) != span {
                content.styles.spans.append(span)
            }
        }

        private static func alignCode(_ value: String) -> UInt8? {
            switch value.lowercased() {
            case "left": 0
            case "right": 1
            case "center", "centre": 2
            case "justify": 3
            default: nil
            }
        }

        mutating func finished() -> SWFHTMLContent {
            if endsWithParagraph, content.text.last == SWFHTMLText.paragraphEnd {
                content.text.removeLast()
            }
            let end = offset
            content.styles.spans.removeAll { $0.start >= end }
            return content
        }
    }
}
