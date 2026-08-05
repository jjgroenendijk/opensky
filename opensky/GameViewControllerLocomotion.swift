// Renderer bridge for the World > Player & Locomotion readout (issues #188 and
// #191). Same shape as the other provider extensions: read and write the live
// renderer on the main thread, and degrade to a documented "unavailable"
// snapshot when there is no renderer (Metal 4 missing).

import AppKit

extension GameViewController: PlayerLocomotionControlProviding {
    var playerLocomotionSnapshot: PlayerLocomotionSnapshot {
        guard let renderer else { return .unavailable }
        let bridge = renderer.locomotion
        return PlayerLocomotionSnapshot(
            rendererAvailable: true,
            walkModeActive: renderer.movementMode.isPlayerControlled,
            status: bridge.status,
            bindings: locomotionBindings(),
            configuration: bridge.configuration,
            activeStates: bridge.graph?.activeStates ?? [],
            firstPersonActiveStates: bridge.firstPersonGraph?.activeStates ?? [],
            variables: locomotionVariables(of: bridge.graph),
            forcedGait: bridge.forcedGait,
            tally: bridge.graph?.tally
        )
    }

    var isSneaking: Bool {
        get { cameraInput.isSneaking }
        set {
            guard cameraInput.isSneaking != newValue else { return }
            cameraInput.toggleSneak()
        }
    }

    var forcedLocomotionGait: LocomotionGait? {
        get { renderer?.locomotion.forcedGait }
        set { renderer?.locomotion.forcedGait = newValue }
    }

    func requestJump() {
        cameraInput.requestJump()
    }

    @discardableResult
    func raiseLocomotionEvent(named name: String) -> Bool {
        renderer?.locomotion.raiseGraphEvent(named: name) ?? false
    }

    func clearLocomotionTrace() {
        renderer?.locomotion.clearMotionTrace()
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

    /// Every name the bridge writes, paired with the value the graph holds. A
    /// name the graph does not declare comes back with a nil value rather than
    /// being dropped, which is what makes a spelling mismatch visible on the
    /// panel instead of doing nothing quietly.
    private func locomotionVariables(
        of graph: BehaviorGraphInstance?
    ) -> [LocomotionVariableSnapshot] {
        let names = LocomotionGraphNames.variables + [LocomotionGraphNames.isFirstPerson]
        return names.map { name in
            LocomotionVariableSnapshot(
                name: name,
                value: graph?.variable(named: name).map(Self.describe)
            )
        }
    }

    private static func describe(_ value: BehaviorVariableValue) -> String {
        switch value {
        case let .bool(flag): flag ? "true" : "false"
        case let .int(number): String(number)
        case let .real(number): String(format: "%.3f", number)
        case let .quad(vector):
            String(format: "%.3f, %.3f, %.3f, %.3f", vector.x, vector.y, vector.z, vector.w)
        }
    }
}
