// Renderer bridge for the World > Player & Locomotion readout (issue #188).
// Same shape as the other provider extensions: read and write the live renderer
// on the main thread, and degrade to a documented "unavailable" snapshot when
// there is no renderer (Metal 4 missing).

import AppKit

extension GameViewController: PlayerLocomotionControlProviding {
    var playerLocomotionSnapshot: PlayerLocomotionSnapshot {
        guard let renderer else { return .unavailable }
        let bridge = renderer.locomotion
        return PlayerLocomotionSnapshot(
            rendererAvailable: true,
            walkModeActive: renderer.movementMode == .walk,
            status: bridge.status,
            bindings: locomotionBindings(),
            configuration: bridge.configuration
        )
    }

    var isSneaking: Bool {
        get { cameraInput.isSneaking }
        set {
            guard cameraInput.isSneaking != newValue else { return }
            cameraInput.toggleSneak()
        }
    }

    func requestJump() {
        cameraInput.requestJump()
    }

    /// The gameplay keys this milestone added, with their live state, so the
    /// panel advertises every binding rather than leaving one to be discovered
    /// by accident.
    private func locomotionBindings() -> [LocomotionBindingSnapshot] {
        [
            LocomotionBindingSnapshot(
                id: "run",
                label: "Run",
                key: "Shift (hold)",
                isActive: renderer?.locomotion.intent.run ?? false
            ),
            LocomotionBindingSnapshot(
                id: "sprint",
                label: "Sprint",
                key: "Option (hold)",
                isActive: cameraInput.isSprinting
            ),
            LocomotionBindingSnapshot(
                id: "sneak",
                label: "Sneak",
                key: "C (toggle)",
                isActive: cameraInput.isSneaking
            ),
            LocomotionBindingSnapshot(
                id: "jump",
                label: "Jump",
                key: "Space",
                isActive: renderer?.walkController.isGrounded == false
            )
        ]
    }
}
