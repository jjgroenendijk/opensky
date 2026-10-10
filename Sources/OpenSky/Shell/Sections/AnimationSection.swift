// World > Environment > Actor animation: enable toggle and playback readout, plus
// the flicker and pulse of placed lights.

import AppKit
import OpenSkyWorld

final class AnimationSection: PanelSectionViewController {
    weak var provider: (any AnimationControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let enabledControl = NSButton(checkboxWithTitle: "Enabled", target: nil, action: nil)
    let lightsControl = NSButton(
        checkboxWithTitle: "Flickering lights", target: nil, action: nil
    )
    private let statsLabel = PanelComponents.statsLabel(identifier: "AnimationStatsLabel")

    override var sectionTitle: String {
        "Actor animation"
    }

    override var sectionIdentifier: String {
        "animation"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any AnimationControlProviding)?) -> Bool {
        provider?.actorAnimationsEnabled == false || provider?.lightAnimationEnabled == false
    }

    static func resetToDefaults(provider: (any AnimationControlProviding)?) {
        provider?.actorAnimationsEnabled = true
        provider?.lightAnimationEnabled = true
    }

    override func makeContentViews() -> [NSView] {
        PanelComponents.configureCheckbox(
            enabledControl, target: self, action: #selector(enabledChanged),
            identifier: "AnimationsEnabledControl"
        )
        PanelComponents.configureCheckbox(
            lightsControl, target: self, action: #selector(lightsChanged),
            identifier: "LightAnimationEnabledControl"
        )
        return [PanelComponents.group([enabledControl, lightsControl]), statsLabel]
    }

    override func syncControls() {
        enabledControl.isEnabled = provider != nil
        enabledControl.state = provider?.actorAnimationsEnabled == true ? .on : .off
        lightsControl.isEnabled = provider != nil
        lightsControl.state = provider?.lightAnimationEnabled == true ? .on : .off
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
            + " · \(provider.animatedLightCount) animated lights"
    }

    @objc private func lightsChanged() {
        provider?.lightAnimationEnabled = lightsControl.state == .on
        finishInteraction()
    }

    @objc private func enabledChanged() {
        provider?.actorAnimationsEnabled = enabledControl.state == .on
        finishInteraction()
    }
}
