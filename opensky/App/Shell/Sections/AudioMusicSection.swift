// World > Audio > Music section (M9.2.3): the verification surface for the MUSC
// playlist director. An enable toggle, a picker that forces one MUSC playlist
// past the cell/region/worldspace precedence chain, a stop button, and a readout
// naming the derived state plus the playlist and track now sounding. Same shape
// as the other audio sections. Sidebar path and control ids: docs/engine/music.md.

import AppKit

final class AudioMusicSection: PanelSectionViewController {
    weak var provider: (any AudioControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    /// First picker entry: hands selection back to the director's precedence
    /// chain rather than naming a playlist.
    nonisolated static let automaticTitle = "None (automatic)"

    let musicEnabledControl = NSButton(
        checkboxWithTitle: "Music playback",
        target: nil,
        action: nil
    )
    let musicTypeControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let stopMusicControl = NSButton(title: "Stop music", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "AudioMusicStatsLabel")

    /// MUSC editor id forced from this panel, or nil while selection is
    /// automatic. Panel-local because forcing is only reachable through this
    /// control, so no provider state records it.
    private(set) var forcedTypeName: String?
    /// Failure reason from the last force attempt; nil after a success.
    private var lastForceError: String?

    override var sectionTitle: String {
        "Music"
    }

    override var sectionIdentifier: String {
        "audioMusic"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider) || forcedTypeName != nil
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
        forcedTypeName = nil
        lastForceError = nil
    }

    /// Provider-visible half of the override state, for the destination-level
    /// mirrors that run without a live panel. A forced playlist is panel-local
    /// state, so only the enable toggle can be judged from here.
    static func isOverridden(provider: (any AudioControlProviding)?) -> Bool {
        guard let provider else { return false }
        return !provider.musicEnabled
    }

    static func resetToDefaults(provider: (any AudioControlProviding)?) {
        guard let provider else { return }
        provider.musicEnabled = true
        // Drops the forced selection: the next streamed cell resolves the
        // playlist through the normal precedence chain again.
        provider.stopMusic()
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            musicEnabledControl, target: self, action: #selector(musicEnabledChanged),
            identifier: "AudioMusicEnabledControl"
        )
        PanelComponents.configurePopUp(
            musicTypeControl, target: self, action: #selector(musicTypeChanged),
            identifier: "AudioMusicTypeControl", width: PanelMetrics.contentWidth
        )
        PanelComponents.configureButton(
            stopMusicControl, target: self, action: #selector(stopMusic),
            identifier: "AudioStopMusicControl"
        )
        return [
            PanelComponents.group([
                musicEnabledControl,
                PanelComponents.caption("Force playlist"),
                musicTypeControl,
                PanelComponents.buttonRow([stopMusicControl])
            ]),
            statsLabel
        ]
    }

    /// Rebuilds the picker from the provider's live MUSC list. The list is empty
    /// until a data root loads, so the automatic entry is always present and the
    /// picker simply stays disabled until there is something to force.
    override func syncControls() {
        let names = provider?.selectableMusicTypeNames ?? []
        musicTypeControl.removeAllItems()
        musicTypeControl.addItem(withTitle: Self.automaticTitle)
        musicTypeControl.addItems(withTitles: names)
        if let forcedTypeName, musicTypeControl.itemTitles.contains(forcedTypeName) {
            musicTypeControl.selectItem(withTitle: forcedTypeName)
        } else {
            musicTypeControl.selectItem(withTitle: Self.automaticTitle)
        }
        musicTypeControl.isEnabled = !names.isEmpty
        musicEnabledControl.isEnabled = provider != nil
        musicEnabledControl.state = provider?.musicEnabled == true ? .on : .off
        stopMusicControl.isEnabled = provider != nil
    }

    @objc private func musicEnabledChanged() {
        provider?.musicEnabled = musicEnabledControl.state == .on
        finishInteraction()
    }

    @objc private func musicTypeChanged() {
        let selected = musicTypeControl.titleOfSelectedItem
        guard let selected, selected != Self.automaticTitle else {
            forcedTypeName = nil
            lastForceError = nil
            // Automatic selection resumes at the next streamed cell.
            provider?.stopMusic()
            finishInteraction()
            return
        }
        forcedTypeName = selected
        lastForceError = provider?.forceMusicType(named: selected)
        finishInteraction()
    }

    @objc private func stopMusic() {
        provider?.stopMusic()
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Music: unavailable"
            return
        }
        var lines = ["State: \(provider.currentMusicStateName)"]
        lines.append("Music: \(provider.currentMusicDescription)")
        if let error = lastForceError ?? provider.lastMusicError {
            lines.append("Music error: \(error)")
        }
        statsLabel.stringValue = lines.joined(separator: "\n")
    }
}
