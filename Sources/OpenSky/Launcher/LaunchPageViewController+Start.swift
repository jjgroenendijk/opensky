// The Launch page's Continue button and the start options for Play. The rules
// live in `LaunchStartForm` and `ContinueOffer`; this file only shows them.

import AppKit
import OpenSkyLaunch
import OpenSkySave

extension LaunchPageViewController: NSTextFieldDelegate {
    static let startKindTitles = ["Title screen", "A cell by name", "A worldspace and grid cell"]

    func configureContinue() {
        PanelComponents.configureButton(
            continueButton, target: self, action: #selector(continueGame),
            identifier: "LaunchContinueControl"
        )
        continueButton.toolTip = "Start Play and load the newest save"
        continueButton.controlSize = .large
        continueLabel.stringValue = "Saves: checking"
    }

    /// Reads the save list off the main actor each time the page shows.
    func refreshContinue() {
        continueCheck?.cancel()
        continueCheck = Task { [weak self] in
            let offer = await OpenSkySaveStore.continueOffer()
            guard !Task.isCancelled else { return }
            self?.show(offer)
        }
    }

    func show(_ offer: ContinueOffer) {
        continueOffer = offer
        let date = offer.date.map { date in
            ", " + date.formatted(date: .abbreviated, time: .shortened)
        } ?? ""
        continueLabel.stringValue = offer.disabledReason.map { "Unavailable: \($0)" }
            ?? "\(offer.title)\(date)"
        continueLabel.toolTip = continueLabel.stringValue
        refreshModes()
    }

    func configureStartControls() {
        startKindPopUp.addItems(withTitles: Self.startKindTitles)
        PanelComponents.configurePopUp(
            startKindPopUp, target: self, action: #selector(startKindChanged),
            identifier: "LaunchStartKindControl"
        )
        startKindPopUp.toolTip = "Where Play starts: the title screen, a cell, or a grid cell"
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
        startWorldspaceField.toolTip = "Only Tamriel streams exterior cells today"
        startXField.toolTip = "The grid X of the exterior cell"
        startYField.toolTip = "The grid Y of the exterior cell"
        startReasonLabel.textColor = .systemOrange
        showStartForm()
    }

    func makeStartGroup() -> NSView {
        let gridRow = NSStackView(views: [startWorldspaceField, startXField, startYField])
        gridRow.spacing = PanelMetrics.rowGap
        return layout.group("Start", [
            startKindPopUp, startCellField, gridRow, startReasonLabel,
            layout.note("Applies to Play. Developer Mode starts as before.")
        ])
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
        for field in [startWorldspaceField, startXField, startYField] {
            field.isHidden = startForm.kind != .exterior
        }
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
        refreshModes()
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

    @objc private func continueGame() {
        guard let slot = continueOffer.slot else { return }
        context.actions?.continueGame(slot: slot)
    }
}
