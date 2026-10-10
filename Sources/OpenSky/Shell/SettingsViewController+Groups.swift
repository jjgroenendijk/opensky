// The Settings groups after the game folder: which plugins.txt the load order comes
// from, the string-table language, and the Skyrim saves folder. The load list offers
// the saves in that folder as imports (docs/engine/ess-import.md#the-saves-folder).

import AppKit
import OpenSkyGameData
import OpenSkySave

extension SettingsViewController {
    func makePluginsTextGroup() -> NSView {
        pluginsPathLabel.textColor = LauncherStyle.text
        pluginsPathLabel.lineBreakMode = .byTruncatingMiddle
        pluginsPathLabel.isSelectable = true
        return layout.group("Plugin load order", [
            pluginsPathLabel, pluginsNoteLabel,
            layout.buttons([
                button("Choose…", #selector(choosePluginsText), "SettingsChoosePluginsTextControl"),
                button(
                    "Search Automatically", #selector(useDefaultPluginsText),
                    "SettingsResetPluginsTextControl"
                )
            ])
        ])
    }

    /// Which `<plugin>_<language>.<ext>` tables localized records use.
    func makeLanguageGroup() -> NSView {
        languageField.placeholderString = LocalizationLanguageSettings.fallback
        languageField.setAccessibilityIdentifier("SettingsLanguageControl")
        languageField.widthAnchor.constraint(equalToConstant: 160).isActive = true
        languageField.toolTip = "The language part of the string table file names"
        return layout.group("String tables", [
            layout.row("Language", languageField), languageNoteLabel,
            layout.buttons([
                button("Apply Override", #selector(applyLanguage), "SettingsApplyLanguageControl"),
                button(
                    "Use Skyrim INI", #selector(useSkyrimLanguage), "SettingsResetLanguageControl"
                )
            ])
        ])
    }

    func makeSavesFolderGroup() -> NSView {
        layout.group("Skyrim saves folder", [
            savesNoteLabel,
            layout.buttons([
                button("Choose…", #selector(chooseSavesFolder), "SettingsChooseSkyrimSavesControl"),
                button("Clear", #selector(clearSavesFolder), "SettingsClearSkyrimSavesControl")
            ])
        ])
    }

    func refreshLanguage(root: GameDataRoot?, problem: String? = nil) {
        let snapshot = LocalizationLanguageSettings.load(root: root)
        if problem == nil {
            languageField.stringValue = snapshot.language
        }
        let note = problem
            ?? "Resolves <plugin>_\(snapshot.language).<ext>. Source: \(snapshot.source)."
        languageNoteLabel.stringValue = note
        languageNoteLabel.toolTip = note
        languageNoteLabel.textColor = problem == nil ? LauncherStyle.textDim : LauncherStyle
            .warning
    }

    /// Without a data root there is nothing to search relative to, so the group
    /// says so rather than guessing.
    func refreshPluginsText(root: GameDataRoot?, problem: String?) {
        guard let root else {
            pluginsPathLabel.stringValue = "Unavailable"
            pluginsNoteLabel.stringValue = problem ?? "Locate the game folder first."
            pluginsNoteLabel.textColor = LauncherStyle.textDim
            return
        }
        let report = PluginLoadOrderReport(resolution: PluginLoadOrder.resolve(root: root))
        pluginsPathLabel.stringValue = report.pluginsTextPath
        pluginsPathLabel.toolTip = report.pluginsTextPath
        let note = (problem ?? report.problem ?? report.sourceNote) + " " + report.summary + "."
        pluginsNoteLabel.stringValue = note
        pluginsNoteLabel.toolTip = note
        pluginsNoteLabel.textColor = problem == nil && report.problem == nil
            ? LauncherStyle.textDim
            : LauncherStyle.warning
    }

    func refreshSavesFolder() {
        let status = ESSSaveFolder.status(of: ESSSaveFolderSetting.folder())
        savesNoteLabel.stringValue = status.message
        savesNoteLabel.toolTip = status.message
        savesNoteLabel.textColor = if case .ready = status {
            LauncherStyle.textDim
        } else {
            LauncherStyle.warning
        }
    }

    @objc func choosePluginsText() {
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

    @objc func useDefaultPluginsText() {
        PluginsTextLocator.clearUserChoice()
        refresh()
        onSettingsChanged?()
    }

    @objc func applyLanguage() {
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

    @objc func useSkyrimLanguage() {
        LocalizationLanguageSettings.clearOverride()
        refresh()
        onSettingsChanged?()
    }

    @objc func chooseSavesFolder() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the folder holding your Skyrim .ess saves."
        panel.prompt = "Use Folder"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            ESSSaveFolderSetting.store(url)
            refreshSavesFolder()
            onSettingsChanged?()
        }
    }

    @objc func clearSavesFolder() {
        ESSSaveFolderSetting.clear()
        refreshSavesFolder()
        onSettingsChanged?()
    }
}
