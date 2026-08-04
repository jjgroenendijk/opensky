// World > Audio > Footsteps section (issue #352): the verification surface for
// the footstep director. An enable toggle, a picker over the tags the current
// footstep set answers to for the gait the player is in, a play button that
// fires one of them without walking, and a readout naming the set, the tag
// list, and the routed/played counts. Same shape as the other audio sections.
// Sidebar path and control ids: docs/engine/audio.md.

import AppKit

final class AudioFootstepsSection: PanelSectionViewController {
    weak var provider: (any AudioControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let footstepsEnabledControl = NSButton(
        checkboxWithTitle: "Footstep playback",
        target: nil,
        action: nil
    )
    let footstepTagControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let playFootstepControl = NSButton(title: "Play footstep", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(
        identifier: "AudioFootstepsStatsLabel"
    )

    /// Failure reason from the last forced footstep; nil after a success.
    private var lastForceError: String?

    override var sectionTitle: String {
        "Footsteps"
    }

    override var sectionIdentifier: String {
        "audioFootsteps"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
        lastForceError = nil
    }

    static func isOverridden(provider: (any AudioControlProviding)?) -> Bool {
        guard let provider else { return false }
        return !provider.footstepsEnabled
    }

    static func resetToDefaults(provider: (any AudioControlProviding)?) {
        provider?.footstepsEnabled = true
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            footstepsEnabledControl, target: self,
            action: #selector(footstepsEnabledChanged),
            identifier: "AudioFootstepsEnabledControl"
        )
        PanelComponents.configurePopUp(
            footstepTagControl, target: self, action: #selector(footstepTagChanged),
            identifier: "AudioFootstepTagControl", width: PanelMetrics.contentWidth
        )
        PanelComponents.configureButton(
            playFootstepControl, target: self, action: #selector(playFootstep),
            identifier: "AudioPlayFootstepControl"
        )
        return [
            PanelComponents.group([
                footstepsEnabledControl,
                PanelComponents.caption("Footstep tag (current gait)"),
                footstepTagControl,
                PanelComponents.buttonRow([playFootstepControl])
            ]),
            statsLabel
        ]
    }

    /// Rebuilds the picker from the tags the current gait's list carries. The
    /// gait changes as the player moves, so the list is rebuilt on every sync
    /// and the previous selection is kept when it survives.
    override func syncControls() {
        let tags = provider?.currentFootstepTags ?? []
        let previous = footstepTagControl.titleOfSelectedItem
        footstepTagControl.removeAllItems()
        footstepTagControl.addItems(withTitles: tags)
        if let previous, tags.contains(previous) {
            footstepTagControl.selectItem(withTitle: previous)
        }
        footstepTagControl.isEnabled = !tags.isEmpty
        footstepsEnabledControl.isEnabled = provider != nil
        footstepsEnabledControl.state = provider?.footstepsEnabled == true ? .on : .off
        playFootstepControl.isEnabled = !tags.isEmpty
    }

    @objc private func footstepsEnabledChanged() {
        provider?.footstepsEnabled = footstepsEnabledControl.state == .on
        finishInteraction()
    }

    @objc private func footstepTagChanged() {
        lastForceError = nil
        finishInteraction()
    }

    @objc private func playFootstep() {
        guard let tag = footstepTagControl.titleOfSelectedItem else { return }
        lastForceError = provider?.forcePlayFootstep(tag: tag)
        finishInteraction()
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Footsteps: unavailable"
            return
        }
        let counts = provider.footstepCounts
        var lines = [
            "Set: \(provider.currentFootstepSetDescription)",
            "Tags: \(tagSummary(provider.currentFootstepTags))",
            "Routed \(counts.routed), played \(counts.played)",
            "Last: \(provider.lastFootstepDescription ?? "none")"
        ]
        if let error = lastForceError ?? provider.lastFootstepError {
            lines.append("Footstep error: \(error)")
        }
        statsLabel.stringValue = lines.joined(separator: "\n")
    }

    private func tagSummary(_ tags: [String]) -> String {
        tags.isEmpty ? "none" : tags.joined(separator: ", ")
    }
}
