// The Asset Optimisation page's controls: identifiers, tooltips, and actions.

import AppKit
import OpenSkyAssetCache
import OpenSkyWorld

extension AssetOptimisationPageViewController {
    func configureControls() {
        PanelComponents.configureCheckbox(
            enabledCheckbox, target: self, action: #selector(toggleEnabled),
            identifier: "AssetOptimisationEnabledControl"
        )
        enabledCheckbox.toolTip = "Load optimised files instead of the archives where they exist"
        qualityPopUp
            .addItems(withTitles: TextureQuality.allCases.map(AssetCacheReadout.qualityTitle))
        PanelComponents.configurePopUp(
            qualityPopUp, target: self, action: #selector(chooseQuality),
            identifier: "AssetOptimisationTextureQualityControl"
        )
        qualityPopUp.toolTip = "Original keeps the shipped textures; the rest pick a smaller format"
        for (group, popUp) in zip(AssetTextureClass.allCases, formatPopUps) {
            popUp.addItems(withTitles: TextureFormatChoice.allCases.map(\.title))
            PanelComponents.configurePopUp(
                popUp, target: self, action: #selector(chooseFormat(_:)),
                identifier: "AssetOptimisationTextureFormat\(group.title)Control"
            )
            popUp.tag = Int(group.rawValue)
            popUp.toolTip = "Force one format for every \(group.title.lowercased()) texture"
        }
        configureDirectLoad()
        configureButtons()
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.widthAnchor.constraint(equalToConstant: LauncherPageLayout.width)
            .isActive = true
        progressBar.setAccessibilityIdentifier("AssetOptimisationProgressIndicator")
        spaceWarningLabel.textColor = LauncherStyle.warning
        problemLabel.textColor = LauncherStyle.warning
        convertReasonLabel.textColor = LauncherStyle.warning
    }

    private func configureDirectLoad() {
        let checkboxes = [
            (directLoadCheckbox, "DirectLoad", "Read optimised files straight into GPU memory"),
            (
                directTexturesCheckbox,
                "DirectLoadTextures",
                AssetOptimisationReadout.directLoadTexturesGain
            ),
            (
                directMeshesCheckbox,
                "DirectLoadMeshes",
                AssetOptimisationReadout.directLoadMeshesGain
            ),
            (
                directAllDisksCheckbox,
                "DirectLoadAllDisks",
                AssetOptimisationReadout.directLoadAllDisksCost
            )
        ]
        for (checkbox, name, toolTip) in checkboxes {
            PanelComponents.configureCheckbox(
                checkbox, target: self, action: #selector(toggleDirectLoad),
                identifier: "AssetOptimisation\(name)Control"
            )
            checkbox.toolTip = toolTip
        }
    }

    private func configureButtons() {
        wire(convertButton, #selector(convert), "Convert", "Convert every file that waits")
        wire(
            cancelButton,
            #selector(cancelConversion),
            "Cancel",
            "Stop; the files converted so far stay"
        )
        wire(
            chooseFolderButton,
            #selector(chooseFolder),
            "ChooseFolder",
            "Pick the folder for optimised files"
        )
        wire(
            defaultFolderButton,
            #selector(useDefaultFolder),
            "ResetFolder",
            "Use the folder in Library/Caches"
        )
        wire(clearButton, #selector(clear), "Clear", "Delete every optimised file")
    }

    /// `name` becomes the id `AssetOptimisation<name>Control`.
    private func wire(_ button: NSButton, _ action: Selector, _ name: String, _ toolTip: String) {
        PanelComponents.configureButton(
            button, target: self, action: action, identifier: "AssetOptimisation\(name)Control"
        )
        button.toolTip = toolTip
    }

    @objc private func toggleEnabled() {
        coordinator.setEnabled(enabledCheckbox.state == .on)
    }

    @objc private func toggleDirectLoad() {
        coordinator.setDirectLoad(DirectGPULoading(
            isEnabled: directLoadCheckbox.state == .on,
            textures: directTexturesCheckbox.state == .on,
            meshes: directMeshesCheckbox.state == .on,
            allDisks: directAllDisksCheckbox.state == .on
        ))
    }

    @objc private func chooseQuality() {
        guard
            let quality =
            TextureQuality(rawValue: UInt8(clamping: qualityPopUp.indexOfSelectedItem))
        else { return }
        coordinator.setTextureQuality(quality)
    }

    @objc private func chooseFormat(_ sender: NSPopUpButton) {
        guard
            let group = AssetTextureClass(rawValue: UInt8(clamping: sender.tag)),
            let choice = TextureFormatChoice(rawValue: UInt8(clamping: sender.indexOfSelectedItem))
        else { return }
        coordinator.setTextureFormat(choice, for: group)
    }

    @objc private func chooseFolder() {
        guard let window = view.window else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.coordinator.setFolder(url)
        }
    }

    @objc private func useDefaultFolder() {
        coordinator.setFolder(nil)
    }

    @objc private func convert() {
        coordinator.startBuild()
    }

    @objc private func cancelConversion() {
        coordinator.cancelBuild()
    }

    @objc private func clear() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete the optimised files?"
        alert.informativeText = "The game loads from the archives until a new conversion."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.coordinator.clear()
        }
    }
}
