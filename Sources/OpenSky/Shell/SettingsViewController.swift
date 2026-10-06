// Settings content: data root, plugins.txt, string-table language, and the Skyrim
// saves folder. The Cmd+, window and the launcher's Settings page both host it.
// Validation lives in engine settings. Choices go to the shared defaults domain so
// the CLI sees them too.

import AppKit
import OpenSkyGameData
import OpenSkyLaunch

final class SettingsViewController: NSViewController {
    /// Called after a persisted engine-load setting changes.
    var onSettingsChanged: (() -> Void)?

    private let pathLabel = NSTextField(wrappingLabelWithString: "")
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let pluginsPathLabel = NSTextField(wrappingLabelWithString: "")
    private let pluginsNoteLabel = NSTextField(wrappingLabelWithString: "")
    private let languageField = NSTextField(string: "")
    private let languageNoteLabel = NSTextField(wrappingLabelWithString: "")
    let savesNoteLabel = NSTextField(wrappingLabelWithString: "")

    override func loadView() {
        view = makeContentView()
        view.frame = NSRect(x: 0, y: 0, width: 520, height: 420)
        refresh()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
    }

    // MARK: - Layout

    private func makeContentView() -> NSView {
        let heading = NSTextField(labelWithString: "Game Data Root")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        pathLabel.isSelectable = true
        pathLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        noteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        noteLabel.textColor = .secondaryLabelColor

        let chooseButton = NSButton(
            title: "Choose…",
            target: self,
            action: #selector(chooseDataRoot)
        )
        chooseButton.setAccessibilityIdentifier("SettingsChooseGameFolderControl")
        let resetButton = NSButton(
            title: "Use Default",
            target: self,
            action: #selector(useDefaultRoot)
        )
        resetButton.setAccessibilityIdentifier("SettingsResetGameFolderControl")
        let buttons = NSStackView(views: [resetButton, chooseButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY

        let pluginsViews = makePluginsTextViews()
        let languageViews = makeLanguageViews()
        let stack = NSStackView(views: [
            heading, pathLabel, noteLabel, buttons
        ] + pluginsViews + languageViews + makeSavesFolderViews())
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)
        stack.setCustomSpacing(12, after: noteLabel)
        stack.setCustomSpacing(20, after: buttons)
        stack.setCustomSpacing(12, after: pluginsNoteLabel)
        if let pluginsButtons = pluginsViews.last {
            stack.setCustomSpacing(20, after: pluginsButtons)
        }
        if let languageButtons = languageViews.last {
            stack.setCustomSpacing(20, after: languageButtons)
        }
        for label in [
            pathLabel, noteLabel, pluginsPathLabel, pluginsNoteLabel, languageNoteLabel,
            savesNoteLabel
        ] {
            label.widthAnchor.constraint(
                equalTo: stack.widthAnchor,
                constant: -32
            ).isActive = true
        }
        return stack
    }

    /// The second group: which plugins.txt the load order comes from.
    private func makePluginsTextViews() -> [NSView] {
        let heading = NSTextField(labelWithString: "Plugin Load Order (plugins.txt)")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        pluginsPathLabel.isSelectable = true
        pluginsPathLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)

        pluginsNoteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        pluginsNoteLabel.textColor = .secondaryLabelColor

        let chooseButton = NSButton(
            title: "Choose…",
            target: self,
            action: #selector(choosePluginsText)
        )
        chooseButton.setAccessibilityIdentifier("SettingsChoosePluginsTextControl")
        let resetButton = NSButton(
            title: "Search Automatically",
            target: self,
            action: #selector(useDefaultPluginsText)
        )
        resetButton.setAccessibilityIdentifier("SettingsResetPluginsTextControl")
        let buttons = NSStackView(views: [resetButton, chooseButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        return [heading, pluginsPathLabel, pluginsNoteLabel, buttons]
    }

    /// Which `<plugin>_<language>.<ext>` tables localized records use.
    private func makeLanguageViews() -> [NSView] {
        let heading = NSTextField(labelWithString: "Localized String Tables")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)

        languageField.placeholderString = LocalizationLanguageSettings.fallback
        languageField.setAccessibilityIdentifier("SettingsLanguageControl")
        languageField.widthAnchor.constraint(equalToConstant: 220).isActive = true

        languageNoteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        languageNoteLabel.textColor = .secondaryLabelColor
        languageNoteLabel.setAccessibilityIdentifier("SettingsLanguageStatsLabel")

        let applyButton = NSButton(
            title: "Apply Override",
            target: self,
            action: #selector(applyLanguage)
        )
        applyButton.setAccessibilityIdentifier("SettingsApplyLanguageControl")
        let resetButton = NSButton(
            title: "Use Skyrim INI",
            target: self,
            action: #selector(useSkyrimLanguage)
        )
        resetButton.setAccessibilityIdentifier("SettingsResetLanguageControl")
        let buttons = NSStackView(views: [resetButton, applyButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        return [heading, languageField, languageNoteLabel, buttons]
    }

    // MARK: - State

    /// Re-resolves the root and updates the labels. `problem` (a failed
    /// choice) shows in place of the source note.
    private func refresh(problem: String? = nil, pluginsProblem: String? = nil) {
        let root = try? GameDataLocator.locate()
        let status = GameFolderStatus { try GameDataLocator.locate() }
        pathLabel.stringValue = status.path ?? "Not located"
        noteLabel.stringValue = problem ?? status.note
        noteLabel.textColor = problem == nil ? .secondaryLabelColor : .systemRed
        refreshPluginsText(root: root, problem: pluginsProblem)
        refreshLanguage(root: root)
        refreshSavesFolder()
    }

    private func refreshLanguage(root: GameDataRoot?, problem: String? = nil) {
        let snapshot = LocalizationLanguageSettings.load(root: root)
        if problem == nil {
            languageField.stringValue = snapshot.language
        }
        languageNoteLabel.stringValue = problem
            ?? "Resolves <plugin>_\(snapshot.language).<ext>. Source: \(snapshot.source)."
        languageNoteLabel.textColor = problem == nil ? .secondaryLabelColor : .systemRed
    }

    /// The plugins.txt group. Without a data root there is nothing to search
    /// relative to, so the group says so rather than guessing.
    private func refreshPluginsText(root: GameDataRoot?, problem: String?) {
        guard let root else {
            pluginsPathLabel.stringValue = "Unavailable"
            pluginsNoteLabel.stringValue = problem
                ?? "Locate the game data root first."
            pluginsNoteLabel.textColor = .secondaryLabelColor
            return
        }
        let report = PluginLoadOrderReport(resolution: PluginLoadOrder.resolve(root: root))
        pluginsPathLabel.stringValue = report.pluginsTextPath
        let note = problem ?? report.problem ?? report.sourceNote
        pluginsNoteLabel.stringValue = note + " " + report.summary + "."
        pluginsNoteLabel.textColor = problem == nil && report.problem == nil
            ? .secondaryLabelColor
            : .systemOrange
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

    @objc private func choosePluginsText() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the plugins.txt holding your load order."
        panel.prompt = "Use File"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            do {
                try PluginsTextLocator.saveUserChoice(path: url.path(percentEncoded: false))
                refresh()
                onSettingsChanged?()
            } catch {
                refresh(pluginsProblem: error.localizedDescription)
            }
        }
    }

    @objc private func useDefaultPluginsText() {
        PluginsTextLocator.clearUserChoice()
        refresh()
        onSettingsChanged?()
    }

    @objc private func applyLanguage() {
        do {
            try LocalizationLanguageSettings.store(languageField.stringValue)
            refresh()
            onSettingsChanged?()
        } catch {
            refreshLanguage(
                root: try? GameDataLocator.locate(),
                problem: error.localizedDescription
            )
        }
    }

    @objc private func useSkyrimLanguage() {
        LocalizationLanguageSettings.clearOverride()
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        self.init(window: window)
        window.contentViewController = settings
        window.setContentSize(NSSize(width: 520, height: 420))
        window.center()
    }
}
