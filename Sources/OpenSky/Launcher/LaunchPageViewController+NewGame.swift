// The Launch page's New game group: where a new game starts, and the Survival Mode
// answer, so the plugin's prompt does not stop a new game unless the player asks for
// it. The start rules live in `LaunchStartForm`; this file only shows them.

import AppKit
import OpenSkyGameData
import OpenSkyLaunch

extension LaunchPageViewController: NSTextFieldDelegate {
    static let startKindTitles = ["Main menu", "A cell by name", "A worldspace and grid cell"]

    func makeNewGameGroup() -> NSView {
        PanelComponents.configureCheckbox(
            survivalModeControl, target: self, action: #selector(survivalModeChanged),
            identifier: "LaunchSurvivalModeControl"
        )
        survivalModeControl.toolTip = "Hunger, fatigue, and cold; change it later in Gameplay"
        PanelComponents.configureCheckbox(
            survivalModeAskControl, target: self, action: #selector(survivalModeChanged),
            identifier: "LaunchSurvivalModeAskControl"
        )
        survivalModeAskControl.toolTip =
            "The game asks in a new game; the Survival Mode box above is then ignored"
        refreshNewGame()
        return layout.group("New game", [
            layout.row("Starts at", startKindPopUp), startCellRow, startGridRow,
            startReasonLabel, layout.toggle(survivalModeControl),
            layout.toggle(survivalModeAskControl)
        ])
    }

    func refreshNewGame() {
        let store = context.playerSettings()
        let ask = store.bool(.survivalModeAsk)
        survivalModeAskControl.state = ask ? .on : .off
        survivalModeControl.state = store.bool(.survivalMode) ? .on : .off
        survivalModeControl.isEnabled = !ask
    }

    @objc private func survivalModeChanged() {
        let store = context.playerSettings()
        store.set(.survivalModeAsk, to: survivalModeAskControl.state == .on ? 1 : 0)
        store.set(.survivalMode, to: survivalModeControl.state == .on ? 1 : 0)
        refreshNewGame()
    }

    func configureStartControls() {
        startKindPopUp.addItems(withTitles: Self.startKindTitles)
        PanelComponents.configurePopUp(
            startKindPopUp, target: self, action: #selector(startKindChanged),
            identifier: "LaunchStartKindControl"
        )
        startKindPopUp.toolTip = "Where a new game starts: the main menu, a cell, or a grid cell"
        let fields = [
            (startCellField, "LaunchStartCellControl", 240.0, "WhiterunBanneredMare"),
            (startWorldspaceField, "LaunchStartWorldspaceControl", 140, "Tamriel"),
            (startXField, "LaunchStartXControl", 60, "X"),
            (startYField, "LaunchStartYControl", 60, "Y")
        ]
        for (field, identifier, width, placeholder) in fields {
            PanelComponents.configureTextField(
                field, identifier: identifier, width: width, placeholder: placeholder
            )
            field.delegate = self
        }
        startCellField.toolTip = "The editor ID of a cell, as the console's coc takes it"
        startWorldspaceField.toolTip = "The editor ID of the worldspace, such as DLC2SolstheimWorld"
        startXField.toolTip = "The grid X of the exterior cell"
        startYField.toolTip = "The grid Y of the exterior cell"
        startReasonLabel.textColor = LauncherStyle.warning
        showStartForm()
    }

    func makeGridFields() -> NSStackView {
        for field in [startWorldspaceField, startXField, startYField] {
            LauncherStyle.style(field)
        }
        let fields = NSStackView(views: [startWorldspaceField, startXField, startYField])
        fields.spacing = PanelMetrics.rowGap
        return fields
    }

    private func showStartForm() {
        startKindPopUp.selectItem(at: startForm.kind.rawValue)
        startCellField.stringValue = startForm.cell
        startWorldspaceField.stringValue = startForm.worldspace
        startXField.stringValue = startForm.x
        startYField.stringValue = startForm.y
        refreshStart()
    }

    /// Shows the reason of an invalid start, and remembers a valid one.
    private func refreshStart() {
        startCellField.isHidden = startForm.kind != .cell
        startCellRow.isHidden = startCellField.isHidden
        for field in [startWorldspaceField, startXField, startYField] {
            field.isHidden = startForm.kind != .exterior
        }
        startGridRow.isHidden = startForm.kind != .exterior
        switch startForm.validate() {
        case let .success(start):
            LaunchPreferences.remember(start)
            startReasonLabel.stringValue = ""
            startReasonLabel.isHidden = true
        case let .failure(problem):
            startReasonLabel.stringValue = "Play is off: \(problem.reason)"
            startReasonLabel.toolTip = startReasonLabel.stringValue
            startReasonLabel.isHidden = false
        }
        refreshPlay()
    }

    func controlTextDidChange(_: Notification) {
        startForm.cell = startCellField.stringValue
        startForm.worldspace = startWorldspaceField.stringValue
        startForm.x = startXField.stringValue
        startForm.y = startYField.stringValue
        refreshStart()
    }

    @objc private func startKindChanged() {
        startForm.kind = LaunchStartForm
            .Kind(rawValue: startKindPopUp.indexOfSelectedItem) ?? .normal
        refreshStart()
    }
}
