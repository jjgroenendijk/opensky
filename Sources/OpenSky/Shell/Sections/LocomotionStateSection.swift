// World > Player & Locomotion > State section: where the player is, the
// resolved gait, and what moved them this step. It repeats the camera-mode
// popup, because the capsule only simulates outside fly mode. Not overridden:
// `CameraSection` owns camera mode's override.

import AppKit
import OpenSkyRendering
import OpenSkyWorld

final class LocomotionStateSection: PanelSectionViewController {
    weak var provider: (any PlayerLocomotionControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    /// Camera mode lives on its own seam, which this section only reads and
    /// writes; the locomotion provider does not carry it.
    weak var cameraProvider: (any CameraControlProviding)? {
        didSet {
            guard isViewLoaded else { return }
            syncControls()
            refreshReadout()
        }
    }

    let cameraModeControl = NSPopUpButton(frame: .zero, pullsDown: false)
    private let statsLabel = PanelComponents.statsLabel(
        identifier: "LocomotionStateStatsLabel"
    )
    private let modes = CameraMovementMode.allCases

    override var sectionTitle: String {
        "State"
    }

    override var sectionIdentifier: String {
        "locomotionState"
    }

    override func makeContentViews() -> [NSView] {
        for mode in modes {
            cameraModeControl.addItem(withTitle: Self.title(for: mode))
        }
        PanelComponents.configurePopUp(
            cameraModeControl, target: self, action: #selector(cameraModeChanged),
            identifier: "LocomotionCameraModeControl"
        )
        return [
            PanelComponents.note(
                "The capsule, the behavior graph and the body are simulated in both walk "
                    + "modes and in neither fly mode. The G key cycles the same three modes "
                    + "this popup lists."
            ),
            cameraModeControl,
            statsLabel
        ]
    }

    override func syncControls() {
        cameraModeControl.isEnabled = cameraProvider != nil
        guard
            let cameraProvider,
            let index = modes.firstIndex(of: cameraProvider.movementMode)
        else { return }
        cameraModeControl.selectItem(at: index)
    }

    override func refreshReadout() {
        guard let provider else {
            statsLabel.stringValue = "Locomotion: unavailable"
            return
        }
        statsLabel.stringValue = PlayerLocomotionReadout.stateText(
            for: provider.playerLocomotionSnapshot
        )
    }

    @objc private func cameraModeChanged() {
        let index = cameraModeControl.indexOfSelectedItem
        guard modes.indices.contains(index) else { return }
        cameraProvider?.movementMode = modes[index]
        finishInteraction()
    }

    /// The same three titles `CameraSection` uses, so one mode reads the same
    /// way on both panels.
    private static func title(for mode: CameraMovementMode) -> String {
        switch mode {
        case .fly: "Fly"
        case .walk: "Walk (first person)"
        case .thirdPerson: "Walk (third person)"
        }
    }
}
