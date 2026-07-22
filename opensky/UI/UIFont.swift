// System-font description for the UI layer (M8.1.1). Value type; resolves to a
// CoreText CTFont at a requested pixel/point size on demand. The system UI font
// keeps text native; bold adds the symbolic trait, falling back to the base
// face when the platform has no bold variant.

import CoreText

struct UIFont: Equatable {
    enum Weight: Int, Equatable {
        case regular = 0
        case bold = 1
    }

    var pointSize: Float
    var weight: Weight

    init(pointSize: Float, weight: Weight = .regular) {
        self.pointSize = pointSize
        self.weight = weight
    }

    /// Atlas cache discriminator so two weights of one glyph id never collide.
    var fontKey: Int {
        weight.rawValue
    }

    /// A CTFont for this face at `size` (points for measurement, pixels for
    /// rasterization). Helvetica backstops a platform without a system UI font.
    func makeCTFont(size: CGFloat) -> CTFont {
        let base = CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        guard weight == .bold else { return base }
        let bold = CTFontCreateCopyWithSymbolicTraits(base, size, nil, .boldTrait, .boldTrait)
        return bold ?? base
    }
}
