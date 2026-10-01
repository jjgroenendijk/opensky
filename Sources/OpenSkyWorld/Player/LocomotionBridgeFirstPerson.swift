// The bridge's first-person half: a second graph over `_1stperson`, stepped with the
// same inputs through the fan-out in `write` and `raise`. The instances share no state
// (`LocomotionBridgeFirstPersonTests`). Only `IsFirstPerson` differs, seeded at attach
// and reset (docs/engine/behavior-state-machines.md, "Transition conditions").

import OpenSkyBehavior
import simd

nonisolated extension LocomotionBridge {
    /// Tells each attached graph which perspective it is. Idempotent, so
    /// calling it from both `init` and `reset` costs one write each.
    public func seedPerspectiveVariables() {
        _ = graph?.setVariable(.bool(false), named: LocomotionGraphNames.isFirstPerson)
        _ = firstPersonGraph?.setVariable(
            .bool(true), named: LocomotionGraphNames.isFirstPerson
        )
    }

    /// One variable write, mirrored onto the first-person graph.
    public func writeToFirstPersonGraph(_ value: BehaviorVariableValue, to name: String) {
        guard let firstPersonGraph else { return }
        if firstPersonGraph.setVariable(value, named: name) {
            updateStatus { $0.noteFirstPersonVariableWritten(name) }
        } else {
            updateStatus { $0.noteFirstPersonVariableMissing(name) }
        }
    }

    /// One edge event, mirrored onto the first-person graph.
    public func raiseOnFirstPersonGraph(_ name: String) {
        guard let firstPersonGraph else { return }
        if firstPersonGraph.raiseEvent(named: name) {
            updateStatus { $0.noteFirstPersonEventRaised(name) }
        } else {
            updateStatus { $0.noteFirstPersonEventMissing(name) }
        }
    }

    /// Steps the first-person graph and publishes its pose. Its root motion is
    /// read and dropped: movement authority belongs to the third-person graph
    /// and the character controller alone.
    public func advanceFirstPersonGraph(deltaTime: Float) {
        guard let firstPersonGraph else { return }
        let result = firstPersonGraph.update(deltaTime: deltaTime)
        updateStatus { $0.noteFirstPersonGraphUpdate(events: result.firedEvents) }
        firstPersonPose.publish(result.bones)
    }
}
