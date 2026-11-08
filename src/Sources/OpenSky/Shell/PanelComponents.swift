// Shared vocabulary for launcher pages. Every page
// destination's controls are built from these metrics + factories so 100 future
// knobs still read as one coherent page. Pure AppKit builders, no state; the
// numbers match the hand-rolled constants the pages used before unification.

import AppKit

/// Fixed geometry shared by every launcher page.
enum PanelMetrics {
    // Three-step vertical rhythm. One spacing value applied everywhere made a
    // checkbox and its slider look as separate as two whole subsystems, so the
    // column read as loose floating blocks. Structure now comes from the step
    // between sections, not from uniform air.

    /// Between controls inside one group (a checkbox and its slider).
    static let rowSpacing: CGFloat = 6
    /// Between control groups within a section.
    static let groupSpacing: CGFloat = 12
    /// Horizontal spacing inside a control row.
    static let rowGap: CGFloat = 8

    static let captionFont = NSFont.systemFont(ofSize: 12)
    static let monoFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    static let monoDigitFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
}

/// Stateless factories for the labels, rows, and controls pages share. Extract
/// only what was already duplicated across pages — keep it small.
enum PanelComponents {
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

    /// Wires a popup button's target/action + accessibility id, and optionally
    /// pins its width so a long item title cannot stretch the page column.
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

    /// Wires a free-text entry field's font, width, placeholder, and
    /// accessibility id. Unlike `configureComboBox` this takes no target or
    /// action: the fields it serves (a FormID to mutate, a save-slot name) are
    /// read when the user presses the button beside them, not on every keystroke
    /// or on end-editing, so an action would fire a mutation the user did not
    /// ask for.
    static func configureTextField(
        _ field: NSTextField,
        identifier: String,
        width: CGFloat,
        placeholder: String? = nil
    ) {
        field.font = PanelMetrics.monoFont
        field.placeholderString = placeholder
        field.widthAnchor.constraint(equalToConstant: width).isActive = true
        field.setAccessibilityIdentifier(identifier)
    }
}
