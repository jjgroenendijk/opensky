// The launcher's Reference Game page: send the Windows game OpenSky's view, import its
// newest save, and look at the newest comparison pair. The sidebar lists it only once a
// reference prefix is set; `make reference-game` starts the game (docs/tools/reference-game.md).

import AppKit
import OpenSkyReference

final class ReferencePageViewController: NSViewController {
    let layout = LauncherPageLayout(pageName: "Reference")
    lazy var prefixLabel = layout.line("ReferencePrefixStatsLabel")
    lazy var viewLabel = layout.line("ReferenceViewStatsLabel")
    lazy var comparisonLabel = layout.line("ReferenceComparisonStatsLabel")
    lazy var captionLabel = layout.line("ReferenceCaptionStatsLabel")
    let comparison = ReferenceComparisonView(width: LauncherPageLayout.width)
    private let modes: [ReferenceComparisonMode] = [.sideBySide, .flip, .difference]
    private let context: LauncherContext

    init(context: LauncherContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        let titles = [
            ("Side by Side", "SideBySide"),
            ("Flip", "Flip"),
            ("Difference", "Difference")
        ]
        let modeButtons = titles.enumerated().map { index, names in
            let button = LauncherButton(title: names.0, target: self, action: #selector(showMode))
            button.tag = index
            button.setAccessibilityIdentifier("Reference\(names.1)Control")
            return button
        }
        let export = LauncherButton(
            title: "Export View",
            target: self,
            action: #selector(exportView)
        )
        export.setAccessibilityIdentifier("ReferenceExportViewControl")
        let load = LauncherButton(
            title: "Import Newest Save",
            target: self,
            action: #selector(importSave)
        )
        load.setAccessibilityIdentifier("ReferenceImportSaveControl")
        view = layout.makeView(title: "Reference Game", groups: [
            layout.group("Same view", [prefixLabel, viewLabel, layout.buttons([export, load])]),
            layout.group("Newest comparison", [
                comparisonLabel, comparison, captionLabel, layout.buttons(modeButtons)
            ])
        ])
        show(ReferenceNotice(ReferencePageActions.exportHint, isProblem: false), in: viewLabel)
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    private func refresh() {
        let status = ReferencePrefixStatus(prefix: ReferenceSettings.prefix())
        show(ReferenceNotice(status.message, isProblem: !status.isReady), in: prefixLabel)
        guard let folder = ReferenceSettings.latestRun() else {
            comparisonLabel.stringValue = "No comparison yet. Run make reference-capture."
            return
        }
        let run = ReferenceComparisonRun(directory: folder)
        comparisonLabel.stringValue = run.readReport()?.summary ?? folder.lastPathComponent
        comparisonLabel.toolTip = folder.path(percentEncoded: false)
        comparison.load(run)
        captionLabel.stringValue = comparison.state.caption
    }

    private func show(_ notice: ReferenceNotice, in label: NSTextField) {
        label.stringValue = notice.message
        label.toolTip = notice.message
        label.textColor = notice.isProblem ? LauncherStyle.warning : LauncherStyle.textDim
    }

    @objc func exportView() {
        let notice = ReferencePageActions.exportView(
            context.actions?.referenceView(), prefix: ReferenceSettings.prefix()
        )
        show(notice, in: viewLabel)
    }

    @objc func importSave() {
        switch ReferencePageActions.newestSave(prefix: ReferenceSettings.prefix()) {
        case let .success(save):
            context.actions?.continueGame(
                slot: SkyrimSaveImportAdapter.slotPrefix + save.path(percentEncoded: false)
            )
        case let .failure(error):
            show(ReferenceNotice(error.message, isProblem: true), in: viewLabel)
        }
    }

    @objc func showMode(_ sender: NSButton) {
        guard modes.indices.contains(sender.tag) else { return }
        comparison.select(modes[sender.tag])
        captionLabel.stringValue = comparison.state.caption
    }
}
