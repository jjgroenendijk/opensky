// The HTML text a script assigns to `htmlText`. `<img>` draws inline in the line of
// text, as GFx does; the styles are in SWFHTMLStyles.swift. See
// docs/engine/as2-display-runtime.md#text.

import Foundation

/// An `<img>` tag: a bitmap the movie exports under `source`, such as "E.png", drawn in
/// the line at `width` by `height` pixels. `verticalSpace` moves it down by that many
/// pixels when negative, as the GFx `vspace` attribute does.
nonisolated public struct SWFInlineImage: Equatable, Sendable {
    public let source: String
    public var width: Float
    public var height: Float
    public var verticalSpace: Float

    public init(source: String, width: Float, height: Float, verticalSpace: Float = 0) {
        self.source = source
        self.width = width
        self.height = height
        self.verticalSpace = verticalSpace
    }
}

/// An inline image after layout: the top-left corner in text-local twips.
nonisolated public struct SWFInlineImagePlacement: Equatable, Sendable {
    public let image: SWFInlineImage
    public let x: Float
    public let y: Float
}

nonisolated public enum SWFHTMLText: Sendable {
    /// Stands for one inline image in the plain text, in the order of `images`.
    public static let imageMarker: Character = "\u{FFFC}"

    /// The plain text with one `imageMarker` per `<img>` tag, and those images in order.
    /// A missing `width` or `height` is 0; the caller fills it from the bitmap.
    static func parse(_ html: String) -> (text: String, images: [SWFInlineImage]) {
        let content = parseStyled(html)
        return (content.text, content.images)
    }

    /// The tags back in place of the image markers, so a script that reads `htmlText`
    /// and assigns it again keeps its pictures.
    public static func restoringImages(in text: String, images: [SWFInlineImage]) -> String {
        var result = ""
        var next = images.makeIterator()
        for character in text {
            if character == imageMarker, let image = next.next() {
                result += "<img src='\(image.source)' width='\(image.width)' "
                    + "height='\(image.height)' vspace='\(image.verticalSpace)'>"
            } else {
                result.append(character)
            }
        }
        return result
    }

    static func image(fromTag body: String) -> SWFInlineImage? {
        let trimmed = body.trimmingCharacters(in: .whitespaces)
        guard trimmed.lowercased().hasPrefix("img"), trimmed.count > 3 else { return nil }
        let attributes = attributes(of: String(trimmed.dropFirst(3)))
        guard let source = attributes["src"], !source.isEmpty else { return nil }
        func number(_ name: String) -> Float {
            attributes[name].flatMap { Float($0.trimmingCharacters(in: .whitespaces)) } ?? 0
        }
        return SWFInlineImage(
            source: source, width: number("width"), height: number("height"),
            verticalSpace: number("vspace")
        )
    }

    /// `name='value'` and `name="value"` pairs; names are lowercased.
    static func attributes(of text: String) -> [String: String] {
        var result: [String: String] = [:]
        var rest = Substring(text)
        while let equals = rest.firstIndex(of: "=") {
            let name = rest[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            var valueStart = rest.index(after: equals)
            while valueStart < rest.endIndex, rest[valueStart] == " " {
                valueStart = rest.index(after: valueStart)
            }
            guard valueStart < rest.endIndex else { break }
            let quote = rest[valueStart]
            if quote == "'" || quote == "\"" {
                let contentStart = rest.index(after: valueStart)
                let end = rest[contentStart...].firstIndex(of: quote) ?? rest.endIndex
                result[name] = String(rest[contentStart ..< end])
                rest = end < rest.endIndex ? rest[rest.index(after: end)...] : ""
            } else {
                let end = rest[valueStart...].firstIndex(of: " ") ?? rest.endIndex
                result[name] = String(rest[valueStart ..< end])
                rest = rest[end...]
            }
        }
        return result
    }
}
