// World > Audio > Voice section (item 17.5): the discoverable half of voice
// playback. Type a substring, pick one of the matching `.fuz` lines, play it at
// the speaker position in front of the camera, and watch the playback clock
// advance on the voice submix.
//
// The picker is a filter over 75,408 files rather than a list of them, so the
// readout always states the true match count beside the number it is showing.
// Exact sidebar path and control ids: docs/engine/audio.md.

import AppKit

final class AudioVoiceSection: PanelSectionViewController {
    weak var provider: (any AudioControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let filterControl = NSTextField(string: "")
    let fileControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let applyFilterControl = NSButton(title: "Filter", target: nil, action: nil)
    let playControl = NSButton(title: "Play line", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "AudioVoiceStatsLabel")

    override var sectionTitle: String {
        "Voice"
    }

    override var sectionIdentifier: String {
        "audioVoice"
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureTextField(
            filterControl,
            identifier: "AudioVoiceFilterControl",
            width: PanelMetrics.contentWidth,
            placeholder: "sound\\voice\\<plugin>\\<voice type>\\"
        )
        PanelComponents.configurePopUp(
            fileControl, target: self, action: #selector(fileChanged),
            identifier: "AudioVoiceFileControl", width: PanelMetrics.contentWidth
        )
        PanelComponents.configureButton(
            applyFilterControl, target: self, action: #selector(applyFilter),
            identifier: "AudioVoiceFilterApplyControl"
        )
        PanelComponents.configureButton(
            playControl, target: self, action: #selector(playSelected),
            identifier: "AudioVoicePlayControl"
        )
        return [
            PanelComponents.note(
                "Plays one dialogue recording — a .fuz container, lip data plus an xWMA "
                    + "stream — as a positional source on the voice submix, placed ahead of "
                    + "the camera. The archives hold tens of thousands of lines, so the "
                    + "picker lists the first matches of the filter and the readout states "
                    + "how many matched in total."
            ),
            PanelComponents.group([
                filterControl,
                PanelComponents.buttonRow([applyFilterControl, playControl]),
                fileControl
            ]),
            statsLabel
        ]
    }

    // MARK: Actions

    @objc private func applyFilter() {
        provider?.voiceFileFilter = filterControl.stringValue
        syncControls()
        refreshReadout()
        finishInteraction()
    }

    @objc private func fileChanged() {
        finishInteraction()
    }

    @objc private func playSelected() {
        guard let name = fileControl.titleOfSelectedItem else { return }
        _ = provider?.playVoiceFile(named: name)
        refreshReadout()
        finishInteraction()
    }

    // MARK: Sync and readout

    override func syncControls() {
        guard let provider else {
            filterControl.isEnabled = false
            fileControl.isEnabled = false
            playControl.isEnabled = false
            return
        }
        if filterControl.stringValue.isEmpty {
            filterControl.stringValue = provider.voiceFileFilter
        }
        let names = provider.selectableVoiceFileNames
        let selected = fileControl.titleOfSelectedItem
        fileControl.removeAllItems()
        fileControl.addItems(withTitles: names)
        if let selected, fileControl.itemTitles.contains(selected) {
            fileControl.selectItem(withTitle: selected)
        }
        filterControl.isEnabled = true
        applyFilterControl.isEnabled = true
        fileControl.isEnabled = !names.isEmpty
        playControl.isEnabled = !names.isEmpty
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Voice: unavailable"
            return
        }
        statsLabel.stringValue = Self.readoutText(
            listed: provider.selectableVoiceFileNames.count,
            matched: provider.voiceFileMatchCount,
            line: provider.currentVoiceDescription,
            playback: provider.voicePlaybackDescription,
            error: provider.lastVoiceError
        )
    }

    /// Pure so the wording is unit tested without a window.
    static func readoutText(
        listed: Int,
        matched: Int,
        line: String?,
        playback: String,
        error: String?
    ) -> String {
        var lines = ["Voice files: \(listed) listed of \(matched) matching"]
        lines.append("Line: \(line ?? "none played yet")")
        if !playback.isEmpty {
            lines.append(playback)
        }
        if let error {
            lines.append("Play failed: \(error)")
        }
        return lines.joined(separator: "\n")
    }
}
