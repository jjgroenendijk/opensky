// World > Environment > Actor animation section: A/B enable toggle + live
// playback readout (issue #98 decomposition).

import AppKit

final class AnimationSection: PanelSectionViewController {
    weak var provider: (any AnimationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "AnimationStatsLabel")

    override var sectionTitle: String {
        "Actor animation"
    }

    override var sectionIdentifier: String {
        "animation"
    }

    override func makeContentViews() -> [NSView] {
        enabledControl.target = self
        enabledControl.action = #selector(enabledChanged)
        enabledControl.setAccessibilityIdentifier("AnimationsEnabledControl")
        return [enabledControl, statsLabel]
    }

    override func syncControls() {
        enabledControl.isEnabled = provider != nil
        enabledControl.state = provider?.actorAnimationsEnabled == true ? .on : .off
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Animation: unavailable"
            return
        }
        let snapshot = provider.animationSnapshot
        let state = provider.actorAnimationsEnabled ? "playing" : "bind pose"
        statsLabel.stringValue = "Animation: \(snapshot.playbackCount) playbacks, "
            + "\(snapshot.updatedBoneCount) bones · \(state) · "
            + String(format: "%.2f ms", snapshot.updateMS)
    }

    @objc private func enabledChanged() {
        provider?.actorAnimationsEnabled = enabledControl.state == .on
        finishInteraction()
    }
}
