// The reference game prefix: the Wine prefix `make reference-setup` builds, which the
// Reference Game page and `openskycli reference` read (docs/tools/reference-game.md).
// It is developer tooling, so the group shows only with "Show details" on.

import AppKit
import OpenSkyReference

extension SettingsViewController {
    func makeReferenceGroup() -> NSView {
        layout.detail(layout.group("Reference game prefix", [
            referenceNoteLabel,
            layout.buttons([
                button(
                    "Choose…",
                    #selector(chooseReferencePrefix),
                    "SettingsChooseReferenceControl"
                ),
                button("Clear", #selector(clearReferencePrefix), "SettingsClearReferenceControl")
            ])
        ]))
    }

    func refreshReferencePrefix() {
        let status = ReferencePrefixStatus(prefix: ReferenceSettings.prefix())
        referenceNoteLabel.stringValue = status.message
        referenceNoteLabel.toolTip = status.message
        referenceNoteLabel.textColor = status.isReady ? LauncherStyle.textDim : LauncherStyle
            .warning
    }

    @objc func chooseReferencePrefix() {
        let message = "Select the Wine prefix that holds Windows Steam and the game."
        chooseFolder(message) { [weak self] url in
            ReferenceSettings.storePrefix(url)
            self?.refreshReferencePrefix()
        }
    }

    @objc func clearReferencePrefix() {
        ReferenceSettings.clearPrefix()
        refreshReferencePrefix()
        onSettingsChanged?()
    }
}
