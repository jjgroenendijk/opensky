// The launcher's first page: Play and a line that says what it will do, the launch
// options, the new game options, and the game files. The game folder is set in
// Settings, or in a picker that opens when none is found. While a world load runs,
// the load panel takes the place of the Play button.

import AppKit
import OpenSkyAssetCache
import OpenSkyGameData
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
    let folderButton = LaunchLinkButton()
    /// The newest save, as "Lydia, level 12, 24 Oct 2026 at 13:25".
    var latestSave = ""
    var continueOffer = ContinueOffer.noSaves
    var continueCheck: Task<Void, Never>?
    let resumeControl = NSButton(checkboxWithTitle: "Resume latest save", target: nil, action: nil)
    let skipMainMenuControl = NSButton(
        checkboxWithTitle: "Skip main menu", target: nil, action: nil
    )
    let fullScreenControl = NSButton(checkboxWithTitle: "Full screen", target: nil, action: nil)
    lazy var skipMainMenuRow = layout.toggle(skipMainMenuControl, indent: 20)
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
        checkboxWithTitle: "Let the game ask about Survival Mode", target: nil, action: nil
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

    lazy var playSummary = layout.line("LaunchPlaySummaryStatsLabel")
    private var playRow = NSView()
    let assetButton = LaunchLinkButton()
    private let loadPanel = WorldLoadPanel()
    private var didOfferFolderPicker = false

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
        view = layout.makeView(title: "OpenSky", groups: [
            playRow,
            loadPanel,
            makeLaunchOptionsGroup(),
            makeNewGameGroup(),
            makeGameFilesGroup()
        ])
        context.assetOptimisation.observe { [weak self] in self?.refreshAssetStatus() }
        refreshAssetStatus()
        refreshGameFolder()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshGameFolder()
        refreshContinue()
        refreshLaunchOptions()
        refreshNewGame()
        let assets = context.assetOptimisation
        if assets.check == nil, assets.activity == .idle {
            assets.startCheck()
        }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        offerFolderPickerOnce()
    }

    /// A new user picks the folder at once instead of finding it in Settings.
    /// A test host skips it, because a sheet would wait for a click.
    private func offerFolderPickerOnce() {
        guard
            !didOfferFolderPicker, !GameDataLocator.isRunningInTestHost,
            !GameFolderStatus().isFound, let window = view.window
        else { return }
        didOfferFolderPicker = true
        GameFolderPicker.chooseUntilValid(for: window) { [weak self] in
            self?.context.actions?.gameFolderDidChange()
        }
    }

    func refreshGameFolder() {
        let status = GameFolderStatus()
        folderButton.show(
            symbol: status.isFound ? "folder" : "exclamationmark.triangle",
            title: status.path ?? "Not found: choose it",
            colour: status.isFound ? LauncherStyle.textDim : LauncherStyle.warning
        )
        folderButton.toolTip = status.isFound ? status.path : status.note
        refreshPlay()
    }

    /// Play needs the game folder and, for a new game, a valid start.
    func refreshPlay() {
        let isFound = GameFolderStatus().isFound
        let startIsValid = (try? startForm.validate().get()) != nil
        let resumes = if case .resume = launchPlan {
            true
        } else {
            false
        }
        playButton.isEnabled = isFound && (startIsValid || resumes)
        playButton.keyEquivalent = playButton.isEnabled ? "\r" : ""
        playSummary.stringValue = playSummaryText
        playSummary.toolTip = playSummary.stringValue
    }

    /// Only the state shows here; the Asset Optimisation page holds the detail.
    func refreshAssetStatus() {
        let state = context.assetOptimisation.status
        assetButton.show(
            symbol: state.symbolName, title: state.title,
            colour: state == .ready ? LauncherStyle.good : state.needsConversion ? LauncherStyle
                .warning : LauncherStyle.textDim
        )
        assetButton.toolTip = state.detail
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
        folderButton.isEnabled = !loading
        if !loading {
            refreshPlay()
        }
    }

    // MARK: - Layout

    private func makePlayRow() -> NSView {
        playButton.widthAnchor.constraint(equalToConstant: 260).isActive = true
        return PanelComponents.group([playButton, playSummary])
    }

    private func makeGameFilesGroup() -> NSView {
        PanelComponents.configureButton(
            folderButton, target: self, action: #selector(openSettings),
            identifier: "LauncherSettingsLinkControl"
        )
        PanelComponents.configureButton(
            assetButton, target: self, action: #selector(openAssetOptimisation),
            identifier: "LauncherAssetOptimisationLinkControl"
        )
        return layout.group("Game files", [
            layout.row("Game folder", folderButton),
            layout.row("Asset Optimisation", assetButton)
        ])
    }

    // MARK: - Actions

    @objc private func play() {
        context.actions?.start(launchPlan)
    }

    @objc private func openAssetOptimisation() {
        context.showPage("assetOptimisation")
    }

    @objc private func openSettings() {
        context.showPage("settings")
    }
}
