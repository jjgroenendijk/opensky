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
    /// Panel/section title in the themed uppercase display treatment.
    static func heading(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.attributedStringValue = Theme.headingAttributed(text, size: 15)
        return label
    }

    /// Sub-heading above a control group.
    static func caption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = PanelMetrics.captionFont
        label.textColor = Theme.parchment
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
        label.textColor = Theme.parchmentDim
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

    /// Wires a popup button's target/action + accessibility id, and optionally
    /// pins its width so a long item title cannot stretch the panel column.
    /// Items are added by the caller (the list is usually data-driven).
    static func configurePopUp(
        _ popUp: NSPopUpButton,
        target: AnyObject,
        action: Selector,
        identifier: String,
        width: CGFloat? = nil
    ) {
        popUp.target = target
        popUp.action = action
        popUp.setAccessibilityIdentifier(identifier)
        if let width {
            popUp.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
    }

    /// Wires an editable combo box's target/action/id + width. Use this where a
    /// knob takes a free-form name that usually comes from a short, live list
    /// (a movie's registered callbacks) — the list autocompletes, and anything
    /// outside it can still be typed. Items are added by the caller.
    static func configureComboBox(
        _ comboBox: NSComboBox,
        target: AnyObject,
        action: Selector,
        identifier: String,
        width: CGFloat
    ) {
        comboBox.target = target
        comboBox.action = action
        comboBox.isEditable = true
        comboBox.completes = true
        comboBox.usesDataSource = false
        comboBox.font = PanelMetrics.monoFont
        comboBox.widthAnchor.constraint(equalToConstant: width).isActive = true
        comboBox.setAccessibilityIdentifier(identifier)
    }

    /// Wires a value label's font + fixed width for readouts beside a slider.
    static func valueLabel(width: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = PanelMetrics.monoDigitFont
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        return label
    }
}
