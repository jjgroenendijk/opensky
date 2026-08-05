// World > Audio > Footsteps section (issue #352): the verification surface for
// the footstep director. An enable toggle, a picker over the tags the current
// footstep set answers to for the gait the player is in, a picker that pins the
// surface material (issue #358), a play button that fires one tag without
// walking, and a readout naming the set, the material, the tag list, and the
// routed/played counts. Same shape as the other audio sections.
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
    let footstepMaterialControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let playFootstepControl = NSButton(title: "Play footstep", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(
        identifier: "AudioFootstepsStatsLabel"
    )

    /// The material menu's first entry: follow whatever the ground contact
    /// reports, which is the default and the behaviour issue #358 delivers.
    private static let groundMaterialTitle = "Ground contact"

    /// The materials behind the menu entries after the first, in menu order.
    private var materialOptions: [FormID] = []

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
        return !provider.footstepsEnabled || provider.forcedFootstepMaterial != nil
    }

    static func resetToDefaults(provider: (any AudioControlProviding)?) {
        provider?.footstepsEnabled = true
        provider?.forcedFootstepMaterial = nil
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
        PanelComponents.configurePopUp(
            footstepMaterialControl, target: self,
            action: #selector(footstepMaterialChanged),
            identifier: "AudioFootstepMaterialControl", width: PanelMetrics.contentWidth
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
                PanelComponents.caption("Surface material"),
                footstepMaterialControl,
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
        syncMaterialControl()
    }

    /// Rebuilds the material menu: the ground-contact entry first, then every
    /// MATT the load order carries. The list only changes when the session's
    /// plugin does, so it is rebuilt in place and the pinned selection is kept.
    private func syncMaterialControl() {
        let options = provider?.footstepMaterialOptions ?? []
        if options.map(\.id) != materialOptions {
            materialOptions = options.map(\.id)
            footstepMaterialControl.removeAllItems()
            footstepMaterialControl.addItems(
                withTitles: [Self.groundMaterialTitle] + options.map(\.name)
            )
        }
        footstepMaterialControl.isEnabled = !materialOptions.isEmpty
        let forced = provider?.forcedFootstepMaterial
        let index = forced.flatMap { materialOptions.firstIndex(of: $0) }
        footstepMaterialControl.selectItem(at: index.map { $0 + 1 } ?? 0)
    }

    @objc private func footstepsEnabledChanged() {
        provider?.footstepsEnabled = footstepsEnabledControl.state == .on
        finishInteraction()
    }

    @objc private func footstepTagChanged() {
        lastForceError = nil
        finishInteraction()
    }

    @objc private func footstepMaterialChanged() {
        let index = footstepMaterialControl.indexOfSelectedItem - 1
        provider?.forcedFootstepMaterial = materialOptions.indices.contains(index)
            ? materialOptions[index]
            : nil
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
            "Material: \(provider.currentFootstepMaterialDescription)",
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
