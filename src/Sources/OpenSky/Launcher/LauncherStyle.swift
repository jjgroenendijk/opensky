// The launcher's look, after the SkyUI mod configuration menu: black panels, white
// and grey condensed text, thin grey rules, and a soft band under the row the
// pointer is on. Original drawing only; Futura Condensed ships with macOS.

import AppKit

enum LauncherStyle {
    static let background = NSColor(white: 0.045, alpha: 1)
    static let sidebarBackground = NSColor(white: 0.0, alpha: 1)
    static let text = NSColor(white: 0.93, alpha: 1)
    static let textDim = NSColor(white: 0.6, alpha: 1)
    static let textDisabled = NSColor(white: 0.36, alpha: 1)
    static let rule = NSColor(white: 1, alpha: 0.22)
    static let faintRule = NSColor(white: 1, alpha: 0.07)
    static let highlight = NSColor(white: 1, alpha: 0.08)
    static let pressed = NSColor(white: 1, alpha: 0.16)
    static let good = NSColor(srgbRed: 0.55, green: 0.8, blue: 0.55, alpha: 1)
    static let warning = NSColor(srgbRed: 0.95, green: 0.66, blue: 0.33, alpha: 1)

    /// Space between a row's edge and its text, so the hover band frames the text.
    static let textInset: CGFloat = 10

    static func font(_ size: CGFloat, bold: Bool = false) -> NSFont {
        NSFont(name: bold ? "Futura-CondensedExtraBold" : "Futura-CondensedMedium", size: size)
            ?? NSFont.systemFont(ofSize: size, weight: bold ? .bold : .medium)
    }

    /// Uppercase tracked text, as the menu draws titles, headings, and buttons.
    static func caps(_ text: String, size: CGFloat, colour: NSColor) -> NSAttributedString {
        NSAttributedString(string: text.uppercased(), attributes: [
            .font: font(size),
            .foregroundColor: colour,
            .kern: size * 0.1
        ])
    }

    /// A 1 pt line of `width` points.
    static func rule(width: CGFloat, colour: NSColor = rule) -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = colour.cgColor
        NSLayoutConstraint.activate([
            line.heightAnchor.constraint(equalToConstant: 1),
            line.widthAnchor.constraint(equalToConstant: width)
        ])
        return line
    }

    /// A pop-up as a row value: no bezel, the menu font, the value's colour.
    static func style(_ popUp: NSPopUpButton) {
        popUp.isBordered = false
        popUp.font = font(15)
        popUp.contentTintColor = text
    }

    /// A text field as a row value: right-aligned on a faint well.
    static func style(_ field: NSTextField) {
        field.isBezeled = false
        field.drawsBackground = true
        field.backgroundColor = highlight
        field.textColor = text
        field.font = font(15)
        field.alignment = .right
    }
}

/// A label whose text sits `LauncherStyle.textInset` in from its left edge, in line
/// with the titles of the rows around it.
final class LauncherText: NSTextField {
    override static var cellClass: AnyClass? {
        get { LauncherInsetCell.self }
        set { _ = newValue }
    }
}

final class LauncherInsetCell: NSTextFieldCell {
    private func inset(_ rect: NSRect) -> NSRect {
        NSRect(
            x: rect.minX + LauncherStyle.textInset, y: rect.minY,
            width: max(rect.width - LauncherStyle.textInset, 0), height: rect.height
        )
    }

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        super.drawingRect(forBounds: inset(rect))
    }

    override func cellSize(forBounds rect: NSRect) -> NSSize {
        var size = super.cellSize(forBounds: inset(rect))
        size.width += LauncherStyle.textInset
        return size
    }

    override func select(
        withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText,
        delegate: Any?, start selStart: Int, length selLength: Int
    ) {
        super.select(
            withFrame: inset(rect), in: controlView, editor: textObj,
            delegate: delegate, start: selStart, length: selLength
        )
    }
}

/// Tracks whether the pointer is inside the view, for a hover band.
class LauncherHoverView: NSView {
    private(set) var isHovered = false {
        didSet { needsDisplay = true }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        ))
    }

    override func mouseEntered(with _: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
    }
}
