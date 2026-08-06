// The bridge's first-person half (issue #190): the second graph instance, fed
// the same state as the first.
//
// Item 14.6 established that one fixed step writes variables, raises edge
// events, updates the graph, and reads root motion back. Item 14.7 adds a
// second graph over the install's `_1stperson` behavior set and runs it through
// exactly the same four steps in the same order, from the same call sites. The
// fan-out lives in `LocomotionBridge.write` and `LocomotionBridge.raise` rather
// than in a second loop here, which is what makes "both graphs see identical
// input state" a property of the code shape instead of a promise: there is one
// place per variable and one place per event, and neither can reach one graph
// without reaching the other.
//
// The two instances share nothing else. `BehaviorGraphInstance` keys its
// runtime state per instance, so stepping one cannot perturb the other's poses,
// events, or state paths — asserted by `LocomotionBridgeFirstPersonTests`.
//
// The one input that deliberately *differs* is `IsFirstPerson`. Both vanilla
// `0_master.hkx` files declare it as a bool initialised to false, and it is the
// variable the graphs' own conditions read to tell the two perspectives apart
// (`docs/engine/behavior-runtime.md`, transition conditions). Writing it true
// on the first-person instance and false on the third-person one is therefore
// not a deviation but the whole point of running two: same state, different
// perspective. It is seeded once at attach and at every reset rather than
// written per step, because it does not change between steps.

import simd

nonisolated extension LocomotionBridge {
    /// Tells each attached graph which perspective it is. Idempotent, so
    /// calling it from both `init` and `reset` costs one write each.
    func seedPerspectiveVariables() {
        _ = graph?.setVariable(.bool(false), named: LocomotionGraphNames.isFirstPerson)
        _ = firstPersonGraph?.setVariable(
            .bool(true), named: LocomotionGraphNames.isFirstPerson
        )
    }

    /// One variable write, mirrored onto the first-person graph.
    func writeToFirstPersonGraph(_ value: BehaviorVariableValue, to name: String) {
        guard let firstPersonGraph else { return }
        if firstPersonGraph.setVariable(value, named: name) {
            updateStatus { $0.noteFirstPersonVariableWritten(name) }
        } else {
            updateStatus { $0.noteFirstPersonVariableMissing(name) }
        }
    }

    /// One edge event, mirrored onto the first-person graph.
    func raiseOnFirstPersonGraph(_ name: String) {
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
    func advanceFirstPersonGraph(deltaTime: Float) {
        guard let firstPersonGraph else { return }
        let result = firstPersonGraph.update(deltaTime: deltaTime)
        updateStatus { $0.noteFirstPersonGraphUpdate(events: result.firedEvents) }
        firstPersonPose.publish(result.bones)
    }
}
