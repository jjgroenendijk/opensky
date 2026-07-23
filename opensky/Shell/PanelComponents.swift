// Shared vocabulary for main-app inspector panels (issue #98). Every sidebar
// destination's controls are built from these metrics + factories so 100 future
// knobs still read as one coherent panel. Pure AppKit builders, no state; the
// numbers match the hand-rolled constants the panels used before unification.

import AppKit

/// Fixed geometry shared by every inspector panel.
enum PanelMetrics {
    /// Width of the sidebar panel slot.
    static let panelWidth: CGFloat = 300
    /// Usable content width inside the panel insets (panelWidth - 2*edgeInset).
    static let contentWidth: CGFloat = 272
    /// Panel edge insets.
    static let edgeInset: CGFloat = 14
    /// Vertical spacing between stacked controls.
    static let rowSpacing: CGFloat = 8
    /// Horizontal spacing inside a control row.
    static let rowGap: CGFloat = 8

    static let headingFont = NSFont.boldSystemFont(ofSize: 15)
    static let captionFont = NSFont.systemFont(ofSize: 12)
    static let noteFont = NSFont.systemFont(ofSize: 11)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let monoDigitFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
}

/// Stateless factories for the labels, rows, and controls panels share. Extract
/// only what was already duplicated across panels — keep it small.
enum PanelComponents {
    /// Bold panel/section title.
    static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = PanelMetrics.headingFont
        return label
    }

    /// Sub-heading above a control group.
    static func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = PanelMetrics.captionFont
        return label
    }

    /// Wrapping tertiary hint sized to the content width.
    static func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = PanelMetrics.noteFont
        label.textColor = .tertiaryLabelColor
        label.widthAnchor.constraint(equalToConstant: PanelMetrics.contentWidth).isActive = true
        return label
    }

    /// Wrapping monospaced live-readout label with a stable accessibility id.
    static func statsLabel(identifier: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: "")
        label.font = PanelMetrics.monoFont
        label.textColor = .secondaryLabelColor
        label.setAccessibilityIdentifier(identifier)
        label.widthAnchor.constraint(equalToConstant: PanelMetrics.contentWidth).isActive = true
        return label
    }

    /// Horizontal slider + trailing value label row.
    static func sliderRow(slider: NSSlider, valueLabel: NSTextField) -> NSStackView {
        let row = NSStackView(views: [slider, valueLabel])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = PanelMetrics.rowGap
        return row
    }

    /// Caption + trailing field row (fixed caption width for column alignment).
    static func labeledFieldRow(
        caption text: String,
        captionWidth: CGFloat,
        field: NSTextField
    ) -> NSStackView {
        let caption = NSTextField(labelWithString: text)
        caption.widthAnchor.constraint(equalToConstant: captionWidth).isActive = true
        let row = NSStackView(views: [caption, field])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = PanelMetrics.rowGap
        return row
    }

    /// Horizontal row of buttons (weather presets, apply/reset).
    static func buttonRow(_ buttons: [NSButton]) -> NSStackView {
        let row = NSStackView(views: buttons)
        row.orientation = .horizontal
        row.alignment = .centerY
        return row
    }

    /// Wires a slider's target/action + width + accessibility id in one call.
    static func configureSlider(
        _ slider: NSSlider,
        target: AnyObject,
        action: Selector,
        identifier: String,
        width: CGFloat,
        continuous: Bool = true
    ) {
        slider.target = target
        slider.action = action
        slider.isContinuous = continuous
        slider.widthAnchor.constraint(equalToConstant: width).isActive = true
        slider.setAccessibilityIdentifier(identifier)
    }

    /// Wires a value label's font + fixed width for readouts beside a slider.
    static func valueLabel(width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = PanelMetrics.monoDigitFont
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }
}
