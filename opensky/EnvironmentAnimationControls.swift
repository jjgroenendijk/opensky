// World > Environment > Actor animation A/B + live playback inspection.

import AppKit

extension EnvironmentPanelViewController {
    func makeAnimationViews() -> [NSView] {
        animationsEnabledControl.target = self
        animationsEnabledControl.action = #selector(animationsEnabledChanged)
        animationsEnabledControl.setAccessibilityIdentifier("AnimationsEnabledControl")
        return [Self.caption("Actor animation"), animationsEnabledControl]
    }

    func syncAnimationControls() {
        animationsEnabledControl.isEnabled = animationProvider != nil
        animationsEnabledControl.state = animationProvider?.actorAnimationsEnabled == true
            ? .on : .off
    }

    @objc private func animationsEnabledChanged() {
        animationProvider?.actorAnimationsEnabled = animationsEnabledControl.state == .on
        refreshStats()
        provider?.refocusGameView()
    }

    func animationReadout() -> String {
        guard let animationProvider else { return "Animation: unavailable" }
        let snapshot = animationProvider.animationSnapshot
        let state = animationProvider.actorAnimationsEnabled ? "playing" : "bind pose"
        return "Animation: \(snapshot.playbackCount) playbacks, "
            + "\(snapshot.updatedBoneCount) bones · \(state) · "
            + String(format: "%.2f ms", snapshot.updateMS)
    }
}
