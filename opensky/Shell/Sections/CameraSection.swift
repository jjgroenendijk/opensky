// World > Camera section: the live pose readout plus the fly/walk selector.
// Movement mode used to be reachable only by pressing `G`; the selector is the
// visible, settable surface the key now accelerates (docs/tools/app-ui.md).
// "Copy pose" puts the shared one-line pose description on the pasteboard so a
// bug report can carry the exact camera that produced a frame.

import AppKit

final class CameraSection: PanelSectionViewController {
    weak var provider: (any CameraControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let movementModeControl = NSPopUpButton(frame: .zero, pullsDown: false)
    let copyPoseControl = NSButton(title: "Copy pose", target: nil, action: nil)
    private let statsLabel = PanelComponents.statsLabel(identifier: "CameraStatsLabel")
    private let modes: [CameraMovementMode] = [.fly, .walk]

    override var sectionTitle: String {
        "Camera"
    }

    override var sectionIdentifier: String {
        "camera"
    }

    override var isOverridden: Bool {
        Self.isOverridden(provider: provider)
    }

    override func resetToDefaults() {
        Self.resetToDefaults(provider: provider)
    }

    static func isOverridden(provider: (any CameraControlProviding)?) -> Bool {
        guard let provider else { return false }
        return provider.movementMode != .fly
    }

    static func resetToDefaults(provider: (any CameraControlProviding)?) {
        provider?.movementMode = .fly
    }

    /// Current readout text; the verification-surface tests read it directly.
    var statsReadout: String {
        statsLabel.stringValue
    }

    override func makeContentViews() -> [NSView] {
        for mode in modes {
            movementModeControl.addItem(withTitle: Self.title(for: mode))
        }
        PanelComponents.configurePopUp(
            movementModeControl, target: self, action: #selector(movementModeChanged),
            identifier: "CameraMovementModeControl"
        )
        PanelComponents.configureButton(
            copyPoseControl, target: self, action: #selector(copyPose),
            identifier: "CameraCopyPoseControl"
        )
        return [
            PanelComponents.group([
                movementModeControl, PanelComponents.buttonRow([copyPoseControl])
            ]),
            statsLabel
        ]
    }

    override func syncControls() {
        movementModeControl.isEnabled = provider != nil
        copyPoseControl.isEnabled = provider != nil
        guard let provider, let index = modes.firstIndex(of: provider.movementMode) else { return }
        movementModeControl.selectItem(at: index)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Camera: unavailable"
            return
        }
        let pose = provider.cameraPose
        let movement = provider.movementConfiguration
        statsLabel.stringValue = String(
            format: """
            Position: %.1f, %.1f, %.1f
            Yaw: %.1f deg  Pitch: %.1f deg
            Cell: %d, %d
            Walk: %.1f units/s (%@)
            Run: %.1f units/s (%@)
            Step: %.1f units (%@)
            """,
            pose.position.x, pose.position.y, pose.position.z,
            pose.yawDegrees, pose.pitchDegrees, pose.cell.x, pose.cell.y,
            movement.walkSpeed.value, movement.walkSpeed.source,
            movement.runSpeed.value, movement.runSpeed.source,
            movement.stepHeight.value, movement.stepHeight.source
        )
    }

    @objc private func movementModeChanged() {
        let index = movementModeControl.indexOfSelectedItem
        guard modes.indices.contains(index) else { return }
        provider?.movementMode = modes[index]
        finishInteraction()
    }

    @objc private func copyPose() {
        guard let provider else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(provider.cameraPoseDescription, forType: .string)
        finishInteraction()
    }

    private static func title(for mode: CameraMovementMode) -> String {
        switch mode {
        case .fly: "Fly"
        case .walk: "Walk"
        }
    }
}
