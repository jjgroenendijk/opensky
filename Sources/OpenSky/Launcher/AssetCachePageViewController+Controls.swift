// The Asset Cache page's controls: identifiers, tooltips, and actions.

import AppKit
import OpenSkyAssetCache
import OpenSkyWorld

extension AssetCachePageViewController {
    func configureControls() {
        PanelComponents.configureCheckbox(
            enabledCheckbox, target: self, action: #selector(toggleEnabled),
            identifier: "AssetCacheEnabledControl"
        )
        enabledCheckbox.toolTip = "Load converted assets from the cache, not the game archives"
        let cores = ProcessInfo.processInfo.activeProcessorCount
        presetPopUp.addItems(withTitles: AssetQualityPreset.allCases.map {
            AssetCacheReadout.presetTitle($0, cores: cores)
        })
        PanelComponents.configurePopUp(
            presetPopUp, target: self, action: #selector(choosePreset),
            identifier: "AssetCachePresetControl"
        )
        presetPopUp.toolTip = "How the cache trades texture quality for GPU memory and build time"
        limitPopUp.addItems(withTitles: Self.limitChoicesGiB.map { "\($0) GiB" })
        PanelComponents.configurePopUp(
            limitPopUp, target: self, action: #selector(chooseLimit),
            identifier: "AssetCacheLimitControl"
        )
        limitPopUp.toolTip = "The cache removes the least recently used files above this size"
        configureLabels()
        configureButtons()
        progressBar.isIndeterminate = false
        progressBar.minValue = 0
        progressBar.maxValue = 1
        progressBar.widthAnchor.constraint(equalToConstant: 440).isActive = true
        progressBar.setAccessibilityIdentifier("AssetCacheBuildProgressIndicator")
    }

    private func configureLabels() {
        let labels: [(NSTextField, String)] = [
            (presetLabel, "AssetCachePresetStatsLabel"), (
                folderLabel,
                "AssetCacheFolderStatsLabel"
            ),
            (sizeLabel, "AssetCacheSizeStatsLabel"), (stateLabel, "AssetCacheStateStatsLabel"),
            (buildLabel, "AssetCacheBuildStatsLabel"), (problemLabel, "AssetCacheProblemStatsLabel")
        ]
        for (label, identifier) in labels {
            label.font = PanelMetrics.monoFont
            label.textColor = Theme.parchmentDim
            label.lineBreakMode = .byTruncatingMiddle
            label.widthAnchor.constraint(equalToConstant: 440).isActive = true
            label.setAccessibilityIdentifier(identifier)
        }
        presetLabel.font = PanelMetrics.captionFont
        problemLabel.textColor = .systemOrange
    }

    private func configureButtons() {
        wire(
            chooseFolderButton,
            #selector(chooseFolder),
            "ChooseFolder",
            "Pick the folder that holds the cache"
        )
        wire(
            defaultFolderButton,
            #selector(useDefaultFolder),
            "ResetFolder",
            "Use the folder in Library/Caches"
        )
        wire(
            buildButton,
            #selector(build),
            "Build",
            "Convert every asset the cache does not hold yet"
        )
        wire(
            cancelButton,
            #selector(cancelBuild),
            "Cancel",
            "Stop the build; the files built so far stay"
        )
        wire(
            checkButton,
            #selector(check),
            "Check",
            "Count the current, stale, and missing cache files"
        )
        wire(clearButton, #selector(clear), "Clear", "Delete every file in the cache")
    }

    /// `name` becomes the id `AssetCache<name>Control`.
    private func wire(_ button: NSButton, _ action: Selector, _ name: String, _ toolTip: String) {
        PanelComponents.configureButton(
            button, target: self, action: action, identifier: "AssetCache\(name)Control"
        )
        button.toolTip = toolTip
    }

    @objc private func toggleEnabled() {
        coordinator.setEnabled(enabledCheckbox.state == .on)
    }

    @objc private func choosePreset() {
        guard
            let preset =
            AssetQualityPreset(rawValue: UInt8(clamping: presetPopUp.indexOfSelectedItem))
        else {
            return
        }
        coordinator.setPreset(preset)
    }

    @objc private func chooseLimit() {
        let index = limitPopUp.indexOfSelectedItem
        guard Self.limitChoicesGiB.indices.contains(index) else { return }
        coordinator.setLimitGiB(Self.limitChoicesGiB[index])
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

    @objc private func build() {
        coordinator.startBuild()
    }

    @objc private func cancelBuild() {
        coordinator.cancelBuild()
    }

    @objc private func check() {
        coordinator.startCheck()
    }

    @objc private func clear() {
        guard let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Clear the asset cache?"
        alert.informativeText = "The game loads from the archives until the cache is built again."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.coordinator.clear()
        }
    }
}
