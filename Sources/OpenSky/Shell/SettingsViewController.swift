// Settings: the game folder and its install check, plugins.txt, the string-table
// language, and the Skyrim saves folder. The Cmd+, window and the launcher's
// Settings page both host it, in the launcher's look. Choices go to the shared
// defaults domain so the CLI sees them too.

import AppKit
import OpenSkyGameData
import OpenSkyLaunch

final class SettingsViewController: NSViewController, LauncherPageRefreshing {
    /// Called after a persisted engine-load setting changes.
    var onSettingsChanged: (() -> Void)?

    let layout = LauncherPageLayout(pageName: "Settings")
    lazy var folderPathLabel = layout.line("SettingsGameFolderStatsLabel", mono: true)
    lazy var folderNoteLabel = layout.line("SettingsGameFolderNoteStatsLabel")
    lazy var installLabel = layout.line("SettingsInstallStatsLabel")
    lazy var installCountsLabel = layout.line("SettingsInstallCountsStatsLabel")
    let installProblemsLabel = LauncherText(labelWithString: "")
    lazy var pluginsPathLabel = layout.line("SettingsPluginsTextStatsLabel", mono: true)
    lazy var pluginsNoteLabel = layout.line("SettingsPluginsNoteStatsLabel")
    let languageField = NSTextField(string: "")
    lazy var languageNoteLabel = layout.line("SettingsLanguageStatsLabel")
    lazy var savesNoteLabel = layout.line("SettingsSkyrimSavesStatsLabel")
    private var installCheck: Task<Void, Never>?

    override func loadView() {
        view = layout.makeView(title: "Settings", groups: [
            makeGameFolderGroup(), makePluginsTextGroup(), makeLanguageGroup(),
            makeSavesFolderGroup()
        ])
        view.frame = NSRect(x: 0, y: 0, width: LauncherPageLayout.minimumPageWidth, height: 560)
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    func refreshGameFolder() {
        refresh()
    }

    func button(_ title: String, _ action: Selector, _ identifier: String) -> LauncherButton {
        let button = LauncherButton(title: title, target: self, action: action)
        button.setAccessibilityIdentifier(identifier)
        return button
    }

    private func makeGameFolderGroup() -> NSView {
        folderPathLabel.textColor = LauncherStyle.text
        folderPathLabel.lineBreakMode = .byTruncatingMiddle
        folderPathLabel.isSelectable = true
        // A failed lookup explains where it searched, so its note may take a few lines.
        folderNoteLabel.maximumNumberOfLines = 3
        folderNoteLabel.lineBreakMode = .byWordWrapping
        folderNoteLabel.preferredMaxLayoutWidth = LauncherPageLayout.width
        installProblemsLabel.font = LauncherStyle.font(14)
        installProblemsLabel.textColor = LauncherStyle.warning
        installProblemsLabel.maximumNumberOfLines = 0
        installProblemsLabel.widthAnchor.constraint(equalToConstant: LauncherPageLayout.width)
            .isActive = true
        installProblemsLabel.setAccessibilityIdentifier("SettingsInstallProblemsStatsLabel")
        return layout.group("Game folder", [
            folderPathLabel, folderNoteLabel, installLabel, layout.detail(installCountsLabel),
            installProblemsLabel,
            layout.buttons([
                button("Choose…", #selector(chooseDataRoot), "SettingsChooseGameFolderControl"),
                button("Use Default", #selector(useDefaultRoot), "SettingsResetGameFolderControl")
            ])
        ])
    }

    // MARK: - State

    /// Re-resolves the root and updates every group. `problem` (a failed choice)
    /// shows in place of the source note.
    func refresh(problem: String? = nil, pluginsProblem: String? = nil) {
        let root = try? GameDataLocator.locate()
        let status = GameFolderStatus()
        folderPathLabel.stringValue = status.path ?? "Not found"
        folderPathLabel.toolTip = status.path
        let note = problem ?? status.note
        folderNoteLabel.stringValue = note
        folderNoteLabel.toolTip = note
        folderNoteLabel.textColor = problem == nil && status.isFound
            ? LauncherStyle.textDim
            : LauncherStyle.warning
        checkInstall(status)
        refreshPluginsText(root: root, problem: pluginsProblem)
        refreshLanguage(root: root)
        refreshSavesFolder()
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
            installCountsLabel.stringValue = "Counts: no folder"
            installProblemsLabel.isHidden = true
            return
        }
        installLabel.stringValue = summary.headline
        installCountsLabel.stringValue = summary.countLine
        installProblemsLabel.stringValue = summary.problemLines
            .map { "Problem: \($0)" }.joined(separator: "\n")
        installProblemsLabel.isHidden = summary.isComplete
    }

    // MARK: - Actions

    @objc private func chooseDataRoot() {
        guard let window = view.window else { return }
        GameFolderPicker.choose(for: window) { [weak self] problem in
            guard let self else { return }
            refresh(problem: problem)
            if problem == nil {
                onSettingsChanged?()
            }
        }
    }

    @objc private func useDefaultRoot() {
        GameDataLocator.clearUserChoice()
        refresh()
        onSettingsChanged?()
    }
}

/// The Cmd+, window around `SettingsViewController`.
final class SettingsWindowController: NSWindowController {
    let settings = SettingsViewController()

    var onSettingsChanged: (() -> Void)? {
        get { settings.onSettingsChanged }
        set { settings.onSettingsChanged = newValue }
    }

    convenience init() {
        let size = NSSize(width: LauncherPageLayout.minimumPageWidth, height: 560)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = LauncherStyle.background
        self.init(window: window)
        window.contentViewController = settings
        window.setContentSize(size)
        window.center()
    }
}
