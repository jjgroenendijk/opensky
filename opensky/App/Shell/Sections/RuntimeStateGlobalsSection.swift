// World > Runtime State > Globals section (M10.2.2): looks a GLOB record up by
// editor ID, shows what the plugin authored beside what the session currently
// resolves, and writes or drops the runtime override.
//
// The readout states the plugin default and the current value separately, and
// states overridden-ness separately again, because those are three different
// facts and the obvious shortcut is wrong twice over. Writing a global the
// value it already held still records an override, and the five clock-projected
// time globals resolve away from their plugin default with no override at all —
// so neither "default equals current" nor "default differs from current"
// answers the question the sidebar's override dot asks.
//
// Overridden-ness for this section is the store's own count of overridden
// globals, and its reset drops every one of them. That mirrors how the Reset
// section treats dirty references: plugin data is the default, and the session's
// deviations from it are what the indicator reports.

import AppKit

final class RuntimeStateGlobalsSection: PanelSectionViewController {
    weak var provider: (any RuntimeStateControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let globalControl = NSComboBox()
    let globalValueControl = NSTextField()
    let globalApplyControl = NSButton(title: "Set", target: nil, action: nil)
    let globalResetControl = NSButton(title: "Reset global", target: nil, action: nil)

    private let statsLabel = PanelComponents.statsLabel(
        identifier: "RuntimeStateGlobalsStatsLabel"
    )
    private var lastActionText = "No global written yet."
    /// Completion list the combo box currently holds, so the 2 Hz sync only
    /// rebuilds it when the loaded plugins actually changed it.
    private var loadedEditorIDs: [String] = []

    override var sectionTitle: String {
        "Globals"
    }

    override var sectionIdentifier: String {
        "runtimeStateGlobals"
    }

    var readout: String {
        statsLabel.stringValue
    }

    /// Editor ID the buttons act on, trimmed. Empty means no selection, which
    /// the readout states rather than guessing at a global.
    var editorID: String {
        globalControl.stringValue.trimmingCharacters(in: .whitespaces)
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any RuntimeStateControlProviding)?) -> Bool {
        (provider?.runtimeStateSnapshot.overriddenGlobalCount ?? 0) > 0
    }

    static func resetToDefaults(provider: (any RuntimeStateControlProviding)?) {
        provider?.resetAllGlobalOverrides()
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureComboBox(
            globalControl, target: self, action: #selector(globalSelected),
            identifier: "RuntimeStateGlobalControl", width: 200
        )
        PanelComponents.configureTextField(
            globalValueControl, identifier: "RuntimeStateGlobalValueControl", width: 100,
            placeholder: "value"
        )
        PanelComponents.configureButton(
            globalApplyControl, target: self, action: #selector(applyValue),
            identifier: "RuntimeStateGlobalApplyControl"
        )
        PanelComponents.configureButton(
            globalResetControl, target: self, action: #selector(resetGlobal),
            identifier: "RuntimeStateGlobalResetControl"
        )
        return [
            PanelComponents.group([
                PanelComponents.note(
                    "Type or pick a GLOB editor ID. Short and long globals round the value "
                        + "onto their declared type. GameHour and the other clock-owned "
                        + "globals move the clock instead of storing an override."
                ),
                globalControl,
                PanelComponents.labeledFieldRow(
                    caption: "Value", captionWidth: 60, field: globalValueControl
                )
            ]),
            PanelComponents.buttonRow([globalApplyControl, globalResetControl]),
            statsLabel
        ]
    }

    // MARK: Actions

    @objc private func globalSelected() {
        globalValueControl.stringValue = provider?.runtimeStateGlobal(editorID: editorID)
            .map { RuntimeStateNumberText.text($0.currentValue) } ?? ""
        finishInteraction()
    }

    @objc private func applyValue() {
        guard !editorID.isEmpty else {
            lastActionText = "Pick a global first."
            finishInteraction()
            return
        }
        guard let value = Float(globalValueControl.stringValue) else {
            lastActionText = "Value must be a number."
            finishInteraction()
            return
        }
        lastActionText = provider?.setGlobalValue(value, editorID: editorID) == true
            ? "Set \(editorID) to \(RuntimeStateNumberText.text(value))."
            : "No write applied to \(editorID)."
        finishInteraction()
    }

    @objc private func resetGlobal() {
        guard !editorID.isEmpty else {
            lastActionText = "Pick a global first."
            finishInteraction()
            return
        }
        lastActionText = provider?.resetGlobalValue(editorID: editorID) == true
            ? "Reset \(editorID) to its plugin default."
            : "Nothing to reset for \(editorID)."
        finishInteraction()
    }

    // MARK: Sync and readout

    override func syncControls() {
        let available = provider?.runtimeStateGlobalEditorIDs ?? []
        guard available != loadedEditorIDs else { return }
        loadedEditorIDs = available
        globalControl.removeAllItems()
        globalControl.addItems(withObjectValues: available)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Runtime state: unavailable"
            return
        }
        let overridden = provider.runtimeStateSnapshot.overriddenGlobalCount
        statsLabel.stringValue = [
            "Globals loaded: \(provider.runtimeStateGlobalEditorIDs.count)"
                + "  Overridden: \(overridden)",
            Self.describe(provider.runtimeStateGlobal(editorID: editorID), editorID: editorID),
            lastActionText
        ].joined(separator: "\n")
    }

    /// The selected global as three separately stated facts. A name nothing
    /// defines reads as that, not as a blank line.
    nonisolated static func describe(
        _ global: RuntimeStateGlobalSnapshot?,
        editorID: String
    ) -> String {
        guard let global else {
            return editorID.isEmpty
                ? "No global selected."
                : "No loaded plugin defines \(editorID)."
        }
        let constant = global.isConstant ? ", constant" : ""
        return [
            "\(global.editorID) (\(global.formIDText), \(global.typeName)\(constant))",
            "  default \(RuntimeStateNumberText.text(global.defaultValue))"
                + "  current \(RuntimeStateNumberText.text(global.currentValue))"
                + "  \(global.isOverridden ? "overridden" : "at default")"
        ].joined(separator: "\n")
    }
}
