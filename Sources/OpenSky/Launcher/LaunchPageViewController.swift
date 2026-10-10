// The launcher's first page: Continue, where Play starts, the two launch modes side
// by side, and what to check before playing. The game folder is set in Settings.
// While a world load runs, the load panel takes the place of the mode buttons.

import AppKit
import OpenSkyAssetCache
import OpenSkyLaunch
import OpenSkySave
import OpenSkyWorld

/// A page that shows game-folder state and must redraw when it changes.
protocol LauncherPageRefreshing: AnyObject {
    func refreshGameFolder()
}

final class LaunchPageViewController: NSViewController, LauncherPageRefreshing {
    let context: LauncherContext
    let layout = LauncherPageLayout(pageName: "Launch")
    lazy var folderLabel = layout.line("LauncherGameFolderStatsLabel")
    let settingsLinkButton = LauncherButton(title: "Open Settings", target: nil, action: nil)
    let continueButton = LauncherButton(title: "Continue", target: nil, action: nil)
    lazy var continueLabel = layout.line("LauncherContinueStatsLabel")
    var continueOffer = ContinueOffer.noSaves
    var continueCheck: Task<Void, Never>?
    let startKindPopUp = NSPopUpButton()
    let startCellField = NSTextField()
    let startWorldspaceField = NSTextField()
    let startXField = NSTextField()
    let startYField = NSTextField()
    lazy var startReasonLabel = layout.line("LaunchStartReasonStatsLabel")
    lazy var startCellRow = layout.row("Cell", startCellField)
    lazy var startGridRow = layout.row("Worldspace and grid cell", makeGridFields())
    var startForm = LaunchStartForm(LaunchPreferences.savedStart())
    private(set) var modeButtons: [(LaunchMode, NSButton)] = []
    private var modeRow = NSView()
    let assetStatus = LauncherStatusView(name: "LauncherAssetOptimisation")
    let assetLinkButton = LauncherButton(
        title: "Open Asset Optimisation",
        target: nil,
        action: nil
    )
    private let loadPanel = WorldLoadPanel()

    init(context: LauncherContext) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        modeRow = makeModeRow()
        loadPanel.isHidden = true
        loadPanel.onCancel = { [weak self] in self?.context.actions?.cancelLoad() }
        configureStartControls()
        configureContinue()
        view = layout.makeView(title: "OpenSky", groups: [
            layout.group("Continue", [continueLabel, layout.buttons([continueButton])]),
            makeStartGroup(),
            modeRow,
            loadPanel,
            makeBeforeYouPlayGroup()
        ])
        context.assetOptimisation.observe { [weak self] in self?.refreshAssetStatus() }
        refreshAssetStatus()
        refreshGameFolder()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshGameFolder()
        refreshContinue()
        let assets = context.assetOptimisation
        if assets.check == nil, assets.activity == .idle {
            assets.startCheck()
        }
    }

    func refreshGameFolder() {
        let status = GameFolderStatus()
        folderLabel.stringValue = status.path.map { "Game folder: \($0)" }
            ?? "Game folder: not found. Choose it in Settings"
        folderLabel.toolTip = status.isFound ? status.path : status.note
        folderLabel.textColor = status.isFound ? LauncherStyle.textDim : LauncherStyle.warning
        refreshModes()
    }

    /// Play needs a valid start; both modes need the game folder.
    func refreshModes() {
        let status = GameFolderStatus()
        let lastMode = LaunchPreferences.lastMode()
        let startIsValid = (try? startForm.validate().get()) != nil
        for (mode, button) in modeButtons {
            button.isEnabled = status.canStart(mode) && (mode != .play || startIsValid)
            button.keyEquivalent = mode == lastMode && button.isEnabled ? "\r" : ""
        }
        continueButton.isEnabled = continueOffer.isEnabled && status.canStart(.play)
    }

    func refreshAssetStatus() {
        let state = context.assetOptimisation.status
        let detail = state.needsConversion
            ? "\(state.detail). The game still starts: waiting files load from the archives"
            : state.detail
        assetStatus.show(
            symbol: state.symbolName, title: "Asset Optimisation: \(state.title)", detail: detail,
            colour: state == .ready ? LauncherStyle.good : state.needsConversion ? LauncherStyle
                .warning : LauncherStyle.textDim
        )
    }

    func showLoad(_ timeline: WorldLoadTimeline, elapsed: Duration) {
        loadViewIfNeeded()
        setLoading(true)
        loadPanel.show(timeline, elapsed: elapsed)
    }

    func endLoad() {
        setLoading(false)
    }

    /// The folder cannot change under a running load, so its buttons pause too.
    private func setLoading(_ loading: Bool) {
        guard isViewLoaded, loadPanel.isHidden == loading else { return }
        modeRow.isHidden = loading
        loadPanel.isHidden = !loading
        for button in [settingsLinkButton, continueButton] {
            button.isEnabled = !loading
        }
        if !loading {
            refreshModes()
        }
    }

    // MARK: - Layout

    private func makeModeRow() -> NSView {
        let columns = LauncherRegistry.modes.map { descriptor -> NSView in
            let button = LauncherButton(
                title: descriptor.title,
                image: NSImage(
                    systemSymbolName: descriptor.symbolName,
                    accessibilityDescription: nil
                )
                    ?? NSImage(),
                target: self,
                action: #selector(startMode(_:))
            )
            button.isPrimary = true
            button.toolTip = descriptor.toolTip
            button.setAccessibilityIdentifier(descriptor.controlIdentifier)
            button.widthAnchor.constraint(equalToConstant: 260).isActive = true
            modeButtons.append((descriptor.mode, button))
            let summary = layout.note(descriptor.summary)
            summary.widthAnchor.constraint(equalToConstant: 260).isActive = true
            summary.setAccessibilityIdentifier(
                descriptor.controlIdentifier.replacingOccurrences(
                    of: "Control",
                    with: "SummaryStatsLabel"
                )
            )
            return PanelComponents.group([button, summary])
        }
        let row = NSStackView(views: columns)
        row.alignment = .top
        row.spacing = 20
        return row
    }

    private func makeBeforeYouPlayGroup() -> NSView {
        PanelComponents.configureButton(
            assetLinkButton, target: self, action: #selector(openAssetOptimisation),
            identifier: "LauncherAssetOptimisationLinkControl"
        )
        assetLinkButton.toolTip = "Convert game files so they load faster"
        PanelComponents.configureButton(
            settingsLinkButton, target: self, action: #selector(openSettings),
            identifier: "LauncherSettingsLinkControl"
        )
        settingsLinkButton.toolTip = "Choose the game folder and the other load settings"
        folderLabel.lineBreakMode = .byTruncatingMiddle
        return layout.group("Before you play", [
            folderLabel, assetStatus, layout.buttons([settingsLinkButton, assetLinkButton])
        ])
    }

    // MARK: - Actions

    @objc private func startMode(_ sender: NSButton) {
        guard let mode = modeButtons.first(where: { $0.1 === sender })?.0 else { return }
        context.actions?.start(mode)
    }

    @objc private func openAssetOptimisation() {
        context.showPage("assetOptimisation")
    }

    @objc private func openSettings() {
        context.showPage("settings")
    }
}
