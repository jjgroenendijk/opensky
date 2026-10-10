// The launcher's first page: the game folder and its check, Continue, where Play
// starts, the two launch modes side by side, and the asset optimisation status.
// While a world load runs, the load panel takes the place of the mode buttons.

import AppKit
import OpenSkyAssetCache
import OpenSkyGameData
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
    lazy var folderPathLabel = layout.line("LauncherGameFolderStatsLabel", mono: true)
    lazy var folderNoteLabel = layout.line("LauncherGameFolderNoteStatsLabel")
    lazy var installLabel = layout.line("LauncherInstallStatsLabel")
    lazy var installCountsLabel = layout.line("LauncherInstallCountsStatsLabel")
    let installProblemsLabel = NSTextField(labelWithString: "")
    private var installCheck: Task<Void, Never>?
    let chooseButton = NSButton(title: "Choose…", target: nil, action: nil)
    let resetButton = NSButton(title: "Use Default", target: nil, action: nil)
    let continueButton = NSButton(title: "Continue", target: nil, action: nil)
    lazy var continueLabel = layout.line("LauncherContinueStatsLabel")
    var continueOffer = ContinueOffer.noSaves
    var continueCheck: Task<Void, Never>?
    let startKindPopUp = NSPopUpButton()
    let startCellField = NSTextField()
    let startWorldspaceField = NSTextField()
    let startXField = NSTextField()
    let startYField = NSTextField()
    lazy var startReasonLabel = layout.line("LaunchStartReasonStatsLabel")
    var startForm = LaunchStartForm(LaunchPreferences.savedStart())
    private(set) var modeButtons: [(LaunchMode, NSButton)] = []
    private var modeRow = NSView()
    let assetStatus = LauncherStatusView(name: "LauncherAssetOptimisation")
    let assetLinkButton = NSButton(title: "Open Asset Optimisation", target: nil, action: nil)
    private let loadPanel = WorldLoadPanel()
    private var problem: String?

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
            makeFolderGroup(),
            layout.group("Continue", [continueButton, continueLabel]),
            makeStartGroup(),
            modeRow,
            loadPanel,
            makeBeforeYouPlayGroup()
        ])
        context.assetOptimisation.observe { [weak self] in self?.refreshAssetStatus() }
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
        folderPathLabel.stringValue = status.path ?? "Not found"
        folderPathLabel.toolTip = status.path
        let note = problem ?? status.note
        folderNoteLabel.stringValue = note
        folderNoteLabel.toolTip = note
        folderNoteLabel.textColor = problem == nil && status.isFound
            ? Theme.parchmentDim
            : .systemOrange
        refreshModes()
        checkInstall(status)
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
            colour: state == .ready ? .systemGreen : state.needsConversion ? .systemOrange : Theme
                .parchmentDim
        )
    }

    /// The check reads every plugin and archive header, so it runs off the main actor.
    private func checkInstall(_ status: GameFolderStatus) {
        installCheck?.cancel()
        let path = status.path ?? GameDataLocator.persistedRootDefaults?
            .string(forKey: GameDataLocator.defaultsKey)
        guard let path else {
            show(nil)
            return
        }
        installLabel.stringValue = "Install: checking"
        installCheck = Task { [weak self] in
            let summary = await GameInstallCheck.check(
                installURL: URL(filePath: path, directoryHint: .isDirectory)
            )
            guard !Task.isCancelled else { return }
            self?.show(summary)
        }
    }

    func show(_ summary: GameInstallSummary?) {
        guard let summary else {
            installLabel.stringValue = "Install: no folder to check"
            installCountsLabel.stringValue = ""
            installProblemsLabel.isHidden = true
            return
        }
        installLabel.stringValue = summary.headline
        installCountsLabel.stringValue = summary.countLine
        installProblemsLabel.stringValue = summary.problemLines
            .map { "Problem: \($0)" }.joined(separator: "\n")
        installProblemsLabel.isHidden = summary.isComplete
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
        for button in [chooseButton, resetButton, continueButton] {
            button.isEnabled = !loading
        }
        if !loading {
            refreshModes()
        }
    }

    // MARK: - Layout

    private func makeFolderGroup() -> NSView {
        folderPathLabel.textColor = Theme.parchment
        folderPathLabel.lineBreakMode = .byTruncatingMiddle
        folderPathLabel.isSelectable = true
        installProblemsLabel.font = PanelMetrics.captionFont
        installProblemsLabel.textColor = .systemOrange
        installProblemsLabel.maximumNumberOfLines = 0
        installProblemsLabel.widthAnchor.constraint(equalToConstant: LauncherPageLayout.width)
            .isActive = true
        installProblemsLabel.setAccessibilityIdentifier("LauncherInstallProblemsStatsLabel")
        PanelComponents.configureButton(
            chooseButton, target: self, action: #selector(chooseFolder),
            identifier: "LauncherChooseGameFolderControl"
        )
        chooseButton.toolTip = "Pick the folder that holds Data/Skyrim.esm"
        PanelComponents.configureButton(
            resetButton, target: self, action: #selector(useDefaultFolder),
            identifier: "LauncherResetGameFolderControl"
        )
        resetButton.toolTip = "Forget the chosen folder and use the default Steam location"
        return layout.group("Game folder", [
            folderPathLabel, folderNoteLabel, installLabel, layout.detail(installCountsLabel),
            installProblemsLabel, PanelComponents.buttonRow([chooseButton, resetButton])
        ])
    }

    private func makeModeRow() -> NSView {
        let columns = LauncherRegistry.modes.map { descriptor -> NSView in
            let button = NSButton(
                title: descriptor.title,
                image: NSImage(
                    systemSymbolName: descriptor.symbolName,
                    accessibilityDescription: nil
                )
                    ?? NSImage(),
                target: self,
                action: #selector(startMode(_:))
            )
            button.imagePosition = .imageLeading
            button.controlSize = .large
            button.toolTip = descriptor.toolTip
            button.setAccessibilityIdentifier(descriptor.controlIdentifier)
            button.widthAnchor.constraint(equalToConstant: 240).isActive = true
            modeButtons.append((descriptor.mode, button))
            let summary = layout.note(descriptor.summary)
            summary.widthAnchor.constraint(equalToConstant: 250).isActive = true
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
        return layout.group("Before you play", [assetStatus, assetLinkButton])
    }

    // MARK: - Actions

    @objc private func startMode(_ sender: NSButton) {
        guard let mode = modeButtons.first(where: { $0.1 === sender })?.0 else { return }
        context.actions?.start(mode)
    }

    @objc private func openAssetOptimisation() {
        context.showPage("assetOptimisation")
    }

    @objc private func chooseFolder() {
        guard let window = view.window else { return }
        GameFolderPicker.choose(for: window) { [weak self] problem in
            self?.problem = problem
            self?.context.actions?.gameFolderDidChange()
        }
    }

    @objc private func useDefaultFolder() {
        GameDataLocator.clearUserChoice()
        problem = nil
        context.actions?.gameFolderDidChange()
    }
}
