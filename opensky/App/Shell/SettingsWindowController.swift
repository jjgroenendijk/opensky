// Settings window (Cmd+,): configure the game data root, plugins.txt load
// order, and localized string-table language. Validation + persistence live
// in AppKit-free engine settings; this file only wires the panel UI. Choices
// persist to the shared defaults domain so the CLI sees them too.
//
// The load order itself is not shown here — the Library > Load Order
// destination lists it, and this window only names the file it comes from.

import AppKit

final class SettingsWindowController: NSWindowController {
    /// Called after a persisted engine-load setting changes.
    var onSettingsChanged: (() -> Void)?

    private let pathLabel = NSTextField(wrappingLabelWithString: "")
    private let noteLabel = NSTextField(wrappingLabelWithString: "")
    private let pluginsPathLabel = NSTextField(wrappingLabelWithString: "")
    private let pluginsNoteLabel = NSTextField(wrappingLabelWithString: "")
    private let languageField = NSTextField(string: "")
    private let languageNoteLabel = NSTextField(wrappingLabelWithString: "")

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        self.init(window: window)
        window.contentView = makeContentView()
        window.center()
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
        let resetButton = NSButton(
            title: "Use Default",
            target: self,
            action: #selector(useDefaultRoot)
        )
        let buttons = NSStackView(views: [resetButton, chooseButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY

        let pluginsViews = makePluginsTextViews()
        let languageViews = makeLanguageViews()
        let stack = NSStackView(views: [
            heading, pathLabel, noteLabel, buttons
        ] + pluginsViews + languageViews)
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
        for label in [
            pathLabel, noteLabel, pluginsPathLabel, pluginsNoteLabel, languageNoteLabel
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
        var root: GameDataRoot?
        do {
            let located = try GameDataLocator.locate()
            root = located
            pathLabel.stringValue = located.installURL.path(percentEncoded: false)
            noteLabel.stringValue = problem ?? Self.sourceNote(for: located.source)
        } catch {
            pathLabel.stringValue = "Not located"
            noteLabel.stringValue = problem ?? error.localizedDescription
        }
        noteLabel.textColor = problem == nil ? .secondaryLabelColor : .systemRed
        refreshPluginsText(root: root, problem: pluginsProblem)
        refreshLanguage(root: root)
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

    private static func sourceNote(for source: GameDataRoot.Source) -> String {
        switch source {
        case .environment:
            "Set by the \(GameDataLocator.environmentKey) environment variable — "
                + "it overrides the choice made here."
        case .userDefaults:
            "Chosen in Settings."
        case .steamDefault:
            "Default Steam install location."
        }
    }

    // MARK: - Actions

    @objc private func chooseDataRoot() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message =
            "Select the Skyrim Special Edition install folder (contains Data/Skyrim.esm)."
        panel.prompt = "Use Folder"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            let path = url.path(percentEncoded: false)
            do {
                try GameDataLocator.saveUserChoice(path: path)
                refresh()
                onSettingsChanged?()
            } catch {
                refresh(
                    problem: "Not a Skyrim SE install: \(path) — "
                        + "expected a folder containing Data/Skyrim.esm."
                )
            }
        }
    }

    @objc private func useDefaultRoot() {
        GameDataLocator.clearUserChoice()
        refresh()
        onSettingsChanged?()
    }

    @objc private func choosePluginsText() {
        guard let window else { return }
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
