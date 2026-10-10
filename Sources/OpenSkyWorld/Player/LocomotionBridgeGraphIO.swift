// The writes that reach every attached graph: one place per variable and per event, so
// both graphs always see the same input. Status changes go through `updateStatus`,
// because `status` is settable only in the class's own file.

import Foundation
import OpenSkyBehavior
import OpenSkyPhysics

nonisolated extension LocomotionBridge {
    /// Writes one variable to every attached graph, recording whether each one
    /// declared it. A name the graph does not carry is reported rather than
    /// dropped, which is how a graph that spells something differently becomes
    /// visible.
    public func write(_ value: BehaviorVariableValue, to name: String) {
        writeToFirstPersonGraph(value, to: name)
        guard let graph else { return }
        if graph.setVariable(value, named: name) {
            updateStatus { $0.noteVariableWritten(name) }
        } else {
            updateStatus { $0.noteVariableMissing(name) }
        }
    }

    /// Raises one event on every attached graph, on the same terms. The dev
    /// control in `LocomotionBridgeDevControls.swift` raises through this path
    /// too, so an event fired from the sidebar is indistinguishable from one
    /// the player produced.
    public func raise(_ name: String) {
        raiseOnFirstPersonGraph(name)
        guard let graph else { return }
        if graph.raiseEvent(named: name) {
            updateStatus { $0.noteEventRaised(name) }
        } else {
            updateStatus { $0.noteEventMissing(name) }
        }
    }
}

nonisolated extension LocomotionBridge {
    /// Ascend on jump, descend on sneak, hold depth otherwise. Both keys are
    /// already bound, so swimming needs no third binding.
    ///
    /// In this satellite rather than in the class body, which is at the
    /// strict-lint length cap.
    public func swimVerticalVelocity(swimming: Bool) -> Float {
        guard swimming else { return 0 }
        let rate = configuration.swimSpeed.value * 0.5
        if intent.jump {
            return rate
        }
        return intent.sneak ? -rate : 0
    }

    /// The blend `hkbRigidBodyRagdollControlsModifier` asks for, or nil when no graph has
    /// run one. Read off the instance, so it cannot go stale.
    public var ragdollBlendDuration: Float? {
        graph?.ragdollBlendDuration
    }

    /// The ragdoll modifier output of the last graph update.
    public var ragdollGraphControls: RagdollGraphControls {
        RagdollGraphControls(
            blendDuration: graph?.ragdollBlendDuration,
            powered: graph?.poweredRagdollControls,
            contactEvent: graph?.ragdollContactEvent
        )
    }
}
