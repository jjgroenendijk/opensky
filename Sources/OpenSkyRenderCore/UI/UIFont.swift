// System-font description for the UI layer, resolved to a CTFont on demand. Bold adds
// the symbolic trait and falls back to the base face.

import CoreText

nonisolated public struct UIFont: Equatable, Sendable {
    public enum Weight: Int, Equatable, Sendable {
        case regular = 0
        case bold = 1
    }

    public var pointSize: Float
    public var weight: Weight

    public init(pointSize: Float, weight: Weight = .regular) {
        self.pointSize = pointSize
        self.weight = weight
    }

    /// Atlas cache discriminator so two weights of one glyph id never collide.
    public var fontKey: Int {
        weight.rawValue
    }

    /// A CTFont for this face at `size` (points for measurement, pixels for
    /// rasterization). Helvetica backstops a platform without a system UI font.
    public func makeCTFont(size: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        guard weight == .bold else { return base }
        let bold = CTFontCreateCopyWithSymbolicTraits(base, size, nil, .boldTrait, .boldTrait)
        return bold ?? base
    }
}
