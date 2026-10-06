// The Skyrim saves folder group of Settings. The load list offers the saves in it as
// imports (docs/engine/ess-import.md#the-saves-folder).

import AppKit
import OpenSkySave

extension SettingsViewController {
    /// The Skyrim saves the load list offers as imports.
    func makeSavesFolderViews() -> [NSView] {
        let heading = NSTextField(labelWithString: "Skyrim Saves Folder")
        heading.font = .boldSystemFont(ofSize: NSFont.systemFontSize)
        savesNoteLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        savesNoteLabel.setAccessibilityIdentifier("SettingsSkyrimSavesStatsLabel")
        let chooseButton = NSButton(
            title: "Choose…", target: self, action: #selector(chooseSavesFolder)
        )
        chooseButton.setAccessibilityIdentifier("SettingsChooseSkyrimSavesControl")
        chooseButton.toolTip = "Pick the folder that holds your Skyrim .ess saves."
        let clearButton = NSButton(
            title: "Clear",
            target: self,
            action: #selector(clearSavesFolder)
        )
        clearButton.setAccessibilityIdentifier("SettingsClearSkyrimSavesControl")
        let buttons = NSStackView(views: [clearButton, chooseButton])
        buttons.orientation = .horizontal
        buttons.alignment = .centerY
        return [heading, savesNoteLabel, buttons]
    }

    func refreshSavesFolder() {
        let status = ESSSaveFolder.status(of: ESSSaveFolderSetting.folder())
        savesNoteLabel.stringValue = status.message
        savesNoteLabel.textColor = if case .ready = status {
            .secondaryLabelColor
        } else {
            .systemOrange
        }
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
