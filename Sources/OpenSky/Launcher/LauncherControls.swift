// The launcher's own controls: a flat, outlined button and a settings row. Both
// draw themselves so the pages keep one look in light and dark system modes.

import AppKit

/// A flat button: an uppercase title in a thin frame. The default button and a
/// primary button draw a brighter frame.
final class LauncherButton: NSButton {
    var isPrimary = false {
        didSet { invalidateIntrinsicContentSize() }
    }

    private var isHovered = false {
        didSet { needsDisplay = true }
    }

    override var isEnabled: Bool {
        didSet { needsDisplay = true }
    }

    override var keyEquivalent: String {
        didSet { needsDisplay = true }
    }

    private var titleSize: CGFloat {
        isPrimary ? 17 : 13
    }

    override var intrinsicContentSize: NSSize {
        let text = LauncherStyle.caps(title, size: titleSize, colour: LauncherStyle.text).size()
        let symbol: CGFloat = image == nil ? 0 : titleSize + 10
        return NSSize(width: ceil(text.width + symbol + 36), height: isPrimary ? 44 : 30)
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

    override func draw(_: NSRect) {
        let frame = NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5))
        let fill = !isEnabled ? NSColor.clear
            : isHighlighted ? LauncherStyle.pressed
            : isHovered ? LauncherStyle.highlight : NSColor.black.withAlphaComponent(0.35)
        fill.setFill()
        frame.fill()
        let isStrong = isEnabled && (isPrimary || keyEquivalent == "\r" || isHovered)
        (isEnabled ? (isStrong ? LauncherStyle.textDim : LauncherStyle.rule) : LauncherStyle
            .faintRule).setStroke()
        frame.stroke()
        let colour = isEnabled ? LauncherStyle.text : LauncherStyle.textDisabled
        let text = LauncherStyle.caps(title, size: titleSize, colour: colour)
        let size = text.size()
        var left = (bounds.width - size.width) / 2
        if let symbol = tinted(image, colour) {
            let side = titleSize
            symbol.draw(
                in: NSRect(x: 14, y: (bounds.height - side) / 2, width: side, height: side),
                from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil
            )
            left = max(left, 14 + side + 10)
        }
        text.draw(at: NSPoint(x: left, y: (bounds.height - size.height) / 2))
    }

    private func tinted(_ image: NSImage?, _ colour: NSColor) -> NSImage? {
        image?.withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [colour]))
    }
}

/// One setting, as the mod menu draws it: the name on the left, the value on the
/// right, a faint rule under it, and a band while the pointer is over it. A click
/// anywhere on the row acts on its control.
final class LauncherRow: LauncherHoverView {
    let titleLabel: NSTextField
    let control: NSView?

    init(title: String, control: NSView?, width: CGFloat = LauncherPageLayout.width) {
        titleLabel = NSTextField(labelWithString: title)
        self.control = control
        super.init(frame: .zero)
        titleLabel.font = LauncherStyle.font(15)
        titleLabel.textColor = LauncherStyle.text
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        var constraints = [
            widthAnchor.constraint(equalToConstant: width),
            heightAnchor.constraint(greaterThanOrEqualToConstant: 34),
            titleLabel.leadingAnchor.constraint(
                equalTo: leadingAnchor,
                constant: LauncherStyle.textInset
            ),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ]
        for view in [titleLabel] + (control.map { [$0] } ?? []) {
            view.translatesAutoresizingMaskIntoConstraints = false
            addSubview(view)
        }
        if let control {
            constraints += [
                control.trailingAnchor.constraint(
                    equalTo: trailingAnchor,
                    constant: -LauncherStyle.textInset
                ),
                control.centerYAnchor.constraint(equalTo: centerYAnchor),
                control.topAnchor.constraint(greaterThanOrEqualTo: topAnchor, constant: 4),
                control.leadingAnchor.constraint(
                    greaterThanOrEqualTo: titleLabel.trailingAnchor,
                    constant: 16
                )
            ]
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    private var isEnabled: Bool {
        guard let control else { return true }
        if let control = control as? NSControl {
            return control.isEnabled
        }
        let controls = control.subviews.compactMap { $0 as? NSControl }
        return controls.isEmpty || controls.contains(where: \.isEnabled)
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        titleLabel.textColor = isEnabled ? LauncherStyle.text : LauncherStyle.textDisabled
    }

    override func draw(_: NSRect) {
        if isHovered, isEnabled {
            LauncherStyle.highlight.setFill()
            bounds.fill()
        }
        LauncherStyle.faintRule.setFill()
        NSRect(x: 0, y: isFlipped ? bounds.maxY - 1 : 0, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with _: NSEvent) {
        guard let control = control as? NSControl, control.isEnabled else { return }
        if control is NSTextField {
            window?.makeFirstResponder(control)
        } else {
            control.performClick(nil)
        }
    }
}
