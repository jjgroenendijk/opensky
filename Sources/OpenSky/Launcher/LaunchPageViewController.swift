// The launcher's first page: the game folder and one button per launch mode.
// While a world load runs, the load panel takes the place of the mode buttons.

import AppKit
import OpenSkyGameData
import OpenSkyLaunch
import OpenSkyWorld

/// A page that shows game-folder state and must redraw when it changes.
protocol LauncherPageRefreshing: AnyObject {
    func refreshGameFolder()
}

final class LaunchPageViewController: NSViewController, LauncherPageRefreshing {
    private weak var actions: (any LauncherActions)?
    private let folderPathLabel = NSTextField(labelWithString: "")
    private let folderNoteLabel = NSTextField(labelWithString: "")
    private let chooseButton = NSButton(title: "Choose…", target: nil, action: nil)
    private let resetButton = NSButton(title: "Use Default", target: nil, action: nil)
    private var modeButtons: [(LaunchMode, NSButton)] = []
    private var modeRow = NSView()
    private let loadPanel = WorldLoadPanel()
    private var problem: String?

    init(actions: any LauncherActions) {
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func loadView() {
        modeRow = makeModeRow()
        loadPanel.isHidden = true
        loadPanel.onCancel = { [weak self] in self?.actions?.cancelLoad() }
        let stack = NSStackView(views: [makeTitle(), makeFolderGroup(), modeRow, loadPanel])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 32
        stack.edgeInsets = NSEdgeInsets(top: 40, left: 32, bottom: 40, right: 32)
        view = stack
        refreshGameFolder()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refreshGameFolder()
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
        let lastMode = LaunchPreferences.lastMode()
        for (mode, button) in modeButtons {
            button.isEnabled = status.canStart(mode)
            button.keyEquivalent = mode == lastMode && button.isEnabled ? "\r" : ""
        }
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
        chooseButton.isEnabled = !loading
        resetButton.isEnabled = !loading
    }

    // MARK: - Layout

    private func makeTitle() -> NSView {
        let title = NSTextField(labelWithAttributedString: Theme.headingAttributed(
            "OpenSky",
            size: 44,
            color: Theme.gold
        ))
        let subtitle = NSTextField(labelWithString: "Skyrim Special Edition")
        subtitle.textColor = Theme.parchmentDim
        let stack = NSStackView(views: [title, subtitle])
        stack.orientation = .vertical
        stack.spacing = 4
        return stack
    }

    private func makeFolderGroup() -> NSView {
        let heading = NSTextField(labelWithAttributedString: Theme.headingAttributed(
            "Game folder",
            size: 13,
            color: Theme.parchment
        ))
        for label in [folderPathLabel, folderNoteLabel] {
            label.widthAnchor.constraint(equalToConstant: 440).isActive = true
        }
        folderPathLabel.lineBreakMode = .byTruncatingMiddle
        folderNoteLabel.lineBreakMode = .byTruncatingTail
        folderPathLabel.font = PanelMetrics.monoFont
        folderPathLabel.textColor = Theme.parchment
        folderPathLabel.isSelectable = true
        folderPathLabel.setAccessibilityIdentifier("LauncherGameFolderStatsLabel")
        folderNoteLabel.font = PanelMetrics.captionFont
        folderNoteLabel.setAccessibilityIdentifier("LauncherGameFolderNoteStatsLabel")
        PanelComponents.configureButton(
            chooseButton,
            target: self,
            action: #selector(chooseFolder),
            identifier: "LauncherChooseGameFolderControl"
        )
        chooseButton.toolTip = "Pick the folder that holds Data/Skyrim.esm"
        PanelComponents.configureButton(
            resetButton,
            target: self,
            action: #selector(useDefaultFolder),
            identifier: "LauncherResetGameFolderControl"
        )
        resetButton.toolTip = "Forget the chosen folder and use the default Steam location"
        let group = PanelComponents.group([
            heading, folderPathLabel, folderNoteLabel,
            PanelComponents.buttonRow([chooseButton, resetButton])
        ])
        group.alignment = .leading
        return group
    }

    private func makeModeRow() -> NSView {
        modeButtons = LauncherRegistry.modes.map { descriptor in
            let button = NSButton(
                title: descriptor.title,
                image: NSImage(
                    systemSymbolName: descriptor.symbolName,
                    accessibilityDescription: nil
                ) ?? NSImage(),
                target: self,
                action: #selector(startMode(_:))
            )
            button.imagePosition = .imageLeading
            button.controlSize = .large
            button.toolTip = descriptor.toolTip
            button.setAccessibilityIdentifier(descriptor.controlIdentifier)
            button.widthAnchor.constraint(greaterThanOrEqualToConstant: 180).isActive = true
            return (descriptor.mode, button)
        }
        let row = PanelComponents.buttonRow(modeButtons.map(\.1))
        row.spacing = 16
        return row
    }

    // MARK: - Actions

    @objc private func startMode(_ sender: NSButton) {
        guard let mode = modeButtons.first(where: { $0.1 === sender })?.0 else { return }
        actions?.start(mode)
    }

    @objc private func chooseFolder() {
        guard let window = view.window else { return }
        GameFolderPicker.choose(for: window) { [weak self] problem in
            self?.problem = problem
            self?.actions?.gameFolderDidChange()
        }
    }

    @objc private func useDefaultFolder() {
        GameDataLocator.clearUserChoice()
        problem = nil
        actions?.gameFolderDidChange()
    }
}
