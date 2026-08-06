// World > Player & Locomotion > State section (issue #191): where the player
// is, which gait resolved, and what moved them this step.
//
// The camera-mode popup is here as well as under `World > World > Camera`
// because this destination is where a user comes to drive locomotion, and the
// capsule only simulates outside fly mode: a panel that showed frozen values
// with no way to unfreeze them from the same screen would fail the app-ui rule
// that a behavior be drivable without knowing a key. Both popups set the same
// renderer state through the same seam, so they cannot drift.
//
// Not overridden: camera mode is the `World > World` destination's
// overridden-ness (`CameraSection`), and claiming it twice would light two dots
// for one setting.

import AppKit

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

    var readout: String {
        statsLabel.stringValue
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
