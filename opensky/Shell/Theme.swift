// Skyrim-inspired look for the dev shell (owner request 2026-07-23): charcoal
// surfaces, parchment text, muted gold accents, condensed uppercase headings.
// Original work — no Bethesda assets. Headings prefer the macOS-bundled Futura
// Condensed Medium face and fall back to the system font when it is absent, so
// nothing is shipped or extracted.

import AppKit

enum Theme {
    // MARK: Surfaces

    /// Window + full-content base. Near-black with a cold cast.
    static let windowBackground = NSColor(srgbRed: 0.075, green: 0.075, blue: 0.086, alpha: 1)
    /// Inspector-panel slot behind controls, one step above the window.
    static let panelBackground = NSColor(srgbRed: 0.104, green: 0.104, blue: 0.118, alpha: 1)
    /// Raised wells (text views, image wells) above the panel surface.
    static let raisedBackground = NSColor(srgbRed: 0.137, green: 0.137, blue: 0.153, alpha: 1)

    // MARK: Ink

    /// Primary text: warm parchment white.
    static let parchment = NSColor(srgbRed: 0.910, green: 0.886, blue: 0.824, alpha: 1)
    /// Secondary text/readouts: faded parchment.
    static let parchmentDim = NSColor(srgbRed: 0.635, green: 0.612, blue: 0.549, alpha: 1)
    /// Accent: muted Nordic gold (also the app accent color asset).
    static let gold = NSColor(srgbRed: 0.788, green: 0.655, blue: 0.361, alpha: 1)
    /// Hairlines + ornament strokes.
    static let divider = gold.withAlphaComponent(0.32)

    // MARK: Type

    /// Display face for headings/section titles. Futura Condensed Medium ships
    /// with macOS; the system face stands in when a stripped install lacks it.
    static func displayFont(size: CGFloat) -> NSFont {
        NSFont(name: "Futura-CondensedMedium", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: .semibold)
    }

    /// Uppercase tracked heading, the signature Skyrim-menu treatment.
    static func headingAttributed(
        _ text: String,
        size: CGFloat,
        color: NSColor = parchment
    ) -> NSAttributedString {
        NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: displayFont(size: size),
                .foregroundColor: color,
                .kern: size * 0.12
            ]
        )
    }

    // MARK: Ornament

    /// 1 pt gold hairline used to separate shell regions.
    static func hairline() -> NSView {
        let line = NSView()
        line.translatesAutoresizingMaskIntoConstraints = false
        line.wantsLayer = true
        line.layer?.backgroundColor = divider.cgColor
        return line
    }
}
