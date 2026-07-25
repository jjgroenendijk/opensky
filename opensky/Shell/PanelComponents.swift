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
    // Three-step vertical rhythm. One spacing value applied everywhere made a
    // checkbox and its slider look as separate as two whole subsystems, so the
    // column read as loose floating blocks. Structure now comes from the step
    // between sections, not from uniform air.

    /// Between controls inside one group (a checkbox and its slider).
    static let rowSpacing: CGFloat = 6
    /// Between control groups within a section.
    static let groupSpacing: CGFloat = 12
    /// Between whole sections in a panel column.
    static let sectionSpacing: CGFloat = 18
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

    /// Wires a checkbox's target/action + accessibility id. Sections declare
    /// their controls as stored properties (no `self` yet), so this configures
    /// an existing button rather than making one — same shape as
    /// `configureSlider`. Every enable/freeze/pause toggle goes through here so
    /// the five hand-rolled copies cannot drift apart again.
    static func configureCheckbox(
        _ checkbox: NSButton,
        target: AnyObject,
        action: Selector,
        identifier: String
    ) {
        checkbox.target = target
        checkbox.action = action
        checkbox.setAccessibilityIdentifier(identifier)
    }

    /// Wires a push button's target/action + accessibility id (weather presets,
    /// apply/reset).
    static func configureButton(
        _ button: NSButton,
        target: AnyObject,
        action: Selector,
        identifier: String
    ) {
        button.target = target
        button.action = action
        button.setAccessibilityIdentifier(identifier)
    }

    /// Stacks tightly-related controls at `rowSpacing` into one unit. A section
    /// returns *groups*; the section stack spaces those at `groupSpacing`, so a
    /// checkbox sits close to the slider it governs while distinct groups stay
    /// visually separate.
    static func group(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = PanelMetrics.rowSpacing
        return stack
    }

    /// Full-width hairline between control groups inside a section.
    static func separator() -> NSView {
        let line = Theme.hairline()
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        line.widthAnchor.constraint(equalToConstant: PanelMetrics.contentWidth).isActive = true
        return line
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
