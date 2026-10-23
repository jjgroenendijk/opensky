// The launcher's first page: Continue, where Play starts, the new game options,
// the two launch modes side by side, and what to check before playing. The game
// folder is set in Settings. While a world load runs, the load panel takes the
// place of the mode buttons.

import AppKit
import OpenSkyAssetCache
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkySave

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
    let survivalModeControl = NSButton(
        checkboxWithTitle: "Survival Mode", target: nil, action: nil
    )
    let survivalModeAskControl = NSButton(
        checkboxWithTitle: "Ask when a new game starts", target: nil, action: nil
    )
    private(set) lazy var playButton: LauncherButton = {
        let button = LauncherButton(
            title: "Play",
            image: NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
                ?? NSImage(),
            target: self,
            action: #selector(play)
        )
        button.isPrimary = true
        button.toolTip = "Start the game"
        button.setAccessibilityIdentifier("LaunchPlayControl")
        return button
    }()

    private var playRow = NSView()
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
        playRow = makePlayRow()
        loadPanel.isHidden = true
        loadPanel.onCancel = { [weak self] in self?.context.actions?.cancelLoad() }
        configureStartControls()
        configureContinue()
        view = layout.makeView(title: "OpenSky", groups: [
            layout.group("Continue", [continueLabel, layout.buttons([continueButton])]),
            makeStartGroup(),
            makeNewGameGroup(),
            playRow,
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
        refreshNewGame()
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
        refreshPlay()
    }

    /// Play needs the game folder and a valid start.
    func refreshPlay() {
        let isFound = GameFolderStatus().isFound
        let startIsValid = (try? startForm.validate().get()) != nil
        playButton.isEnabled = isFound && startIsValid
        playButton.keyEquivalent = playButton.isEnabled ? "\r" : ""
        continueButton.isEnabled = continueOffer.isEnabled && isFound
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
        playRow.isHidden = loading
        loadPanel.isHidden = !loading
        for button in [settingsLinkButton, continueButton] {
            button.isEnabled = !loading
        }
        if !loading {
            refreshPlay()
        }
    }

    // MARK: - Layout

    private func makePlayRow() -> NSView {
        playButton.widthAnchor.constraint(equalToConstant: 260).isActive = true
        let summary = layout.note("The game, from the start you choose")
        summary.widthAnchor.constraint(equalToConstant: 260).isActive = true
        summary.setAccessibilityIdentifier("LaunchPlaySummaryStatsLabel")
        return PanelComponents.group([playButton, summary])
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

    @objc private func play() {
        context.actions?.play()
    }

    @objc private func openAssetOptimisation() {
        context.showPage("assetOptimisation")
    }

    @objc private func openSettings() {
        context.showPage("settings")
    }
}
