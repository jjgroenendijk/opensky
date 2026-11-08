// The launcher's Reference Game page: start OpenSky and the Windows game side by side,
// send the Windows game OpenSky's view, capture both, and look at the newest pair
// (docs/tools/reference-game.md).

import AppKit
import OpenSkyGameData
import OpenSkyReference

final class ReferencePageViewController: NSViewController {
    let layout = LauncherPageLayout()
    lazy var prefixLabel = layout.line("ReferencePrefixStatsLabel")
    lazy var startLabel = layout.line("ReferenceStartStatsLabel")
    lazy var viewLabel = layout.line("ReferenceViewStatsLabel")
    lazy var comparisonLabel = layout.line("ReferenceComparisonStatsLabel")
    lazy var captionLabel = layout.line("ReferenceCaptionStatsLabel")
    let lowGraphicsControl = NSButton(
        checkboxWithTitle: "Low graphics in both games", target: nil, action: nil
    )
    let newestSaveControl = NSButton(
        checkboxWithTitle: "Both games load this Windows save", target: nil, action: nil
    )
    let savePopUp = NSPopUpButton(frame: .zero, pullsDown: false)
    /// The reference saves the pop-up lists, newest first.
    var saves: [URL] = []
    let comparison = ReferenceComparisonView(width: LauncherPageLayout.width)
    private let modes: [ReferenceComparisonMode] = [.sideBySide, .flip, .difference]
    let context: LauncherContext
    /// The setting each checkbox writes.
    var settingKeys: [ObjectIdentifier: SettingKey<Bool>] = [:]

    init(context: LauncherContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        view = layout.makeView(title: "Reference Game", groups: [
            layout.group("Windows game", [
                prefixLabel,
                layout.buttons([button("Choose Prefix…", #selector(choosePrefix), "ChoosePrefix")])
            ]),
            makeStartGroup(),
            layout.group("Same view", [
                viewLabel,
                layout.buttons([
                    button("Send View", #selector(sendView), "SendView"),
                    button("Follow Windows Game", #selector(followReference), "Follow"),
                    button("Capture Both", #selector(captureBoth), "Capture"),
                    button("Import Newest Save", #selector(importSave), "ImportSave")
                ])
            ]),
            layout.group("Newest comparison", [
                comparisonLabel, comparison, captionLabel, layout.buttons(modeButtons())
            ])
        ])
        show(ReferenceNotice(ReferencePageActions.exportHint, isProblem: false), in: viewLabel)
        refresh()
    }

    private func makeStartGroup() -> NSView {
        configure(
            lowGraphicsControl, ReferenceSettings.lowGraphicsSideBySide, "LowGraphics",
            "Both games share one GPU. Sets OpenSky's Graphics preset and the Windows game's "
                + "SkyrimPrefs.ini to Low."
        )
        configure(
            newestSaveControl, ReferenceSettings.startsFromNewestSave, "NewestSave",
            "OpenSky imports the save; the Windows game loads it through the bridge plugin."
        )
        savePopUp.setAccessibilityIdentifier("ReferenceSaveControl")
        savePopUp.toolTip = "The Windows game's saves, newest first."
        show(ReferenceNotice(ReferencePageActions.startHint, isProblem: false), in: startLabel)
        context.actions?.referenceSession.onStatus = { [weak self] notice in
            guard let self else { return }
            show(notice, in: startLabel)
        }
        return layout.group("Play side by side", [
            layout.toggle(lowGraphicsControl),
            layout.toggle(newestSaveControl),
            layout.row("Save", savePopUp),
            layout.buttons([
                button("Start Both", #selector(startBoth), "StartBoth"),
                button("Start Windows Game", #selector(startReferenceOnly), "StartReference")
            ]),
            startLabel
        ])
    }

    private func configure(
        _ control: NSButton, _ key: SettingKey<Bool>, _ name: String, _ tip: String
    ) {
        control.target = self
        control.action = #selector(toggleSetting)
        control.setAccessibilityIdentifier("Reference\(name)Control")
        control.toolTip = tip
        control.state = SettingsStore.shared.value(key) ? .on : .off
        settingKeys[ObjectIdentifier(control)] = key
    }

    private func modeButtons() -> [NSButton] {
        let titles = [
            ("Side by Side", "SideBySide"),
            ("Flip", "Flip"),
            ("Difference", "Difference")
        ]
        return titles.enumerated().map { index, names in
            let button = button(names.0, #selector(showMode), names.1)
            button.tag = index
            return button
        }
    }

    private func button(_ title: String, _ action: Selector, _ name: String) -> NSButton {
        let button = LauncherButton(title: title, target: self, action: action)
        button.setAccessibilityIdentifier("Reference\(name)Control")
        return button
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    func refresh() {
        for control in [lowGraphicsControl, newestSaveControl] {
            if let key = settingKeys[ObjectIdentifier(control)] {
                control.state = SettingsStore.shared.value(key) ? .on : .off
            }
        }
        let status = ReferencePrefixStatus(prefix: ReferenceSettings.prefix())
        show(ReferenceNotice(status.message, isProblem: !status.isReady), in: prefixLabel)
        refreshSaves()
        guard let folder = ReferenceSettings.latestRun() else {
            comparisonLabel.stringValue = "No comparison yet. Start both games, then Capture Both."
            return
        }
        let run = ReferenceComparisonRun(directory: folder)
        comparisonLabel.stringValue = run.readReport()?.summary ?? folder.lastPathComponent
        comparisonLabel.toolTip = folder.path(percentEncoded: false)
        comparison.load(run)
        captionLabel.stringValue = comparison.state.caption
    }

    func show(_ notice: ReferenceNotice, in label: NSTextField) {
        label.stringValue = notice.message
        label.toolTip = notice.message
        label.textColor = notice.isProblem ? LauncherStyle.warning : LauncherStyle.textDim
    }

    @objc func showMode(_ sender: NSButton) {
        guard modes.indices.contains(sender.tag) else { return }
        comparison.select(modes[sender.tag])
        captionLabel.stringValue = comparison.state.caption
    }
}
