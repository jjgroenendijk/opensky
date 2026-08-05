// The two writes that reach every attached graph (issues #190 and #191).
//
// One call site per variable and one per event, both fanning out here. That is
// what makes "both graphs see identical input state" a property of the code
// shape rather than a promise: nothing can reach one graph without reaching the
// other, because there is only one place that reaches either.
//
// A satellite of `LocomotionBridge.swift` for the type-length cap. The status
// mutations go through `updateStatus` because `status` is settable only inside
// the class's own file, which is the narrow lending the bridge already does for
// its first-person half.

import Foundation

nonisolated extension LocomotionBridge {
    /// Writes one variable to every attached graph, recording whether each one
    /// declared it. A name the graph does not carry is reported rather than
    /// dropped, which is how a graph that spells something differently becomes
    /// visible.
    func write(_ value: BehaviorVariableValue, to name: String) {
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
    func raise(_ name: String) {
        raiseOnFirstPersonGraph(name)
        guard let graph else { return }
        if graph.raiseEvent(named: name) {
            updateStatus { $0.noteEventRaised(name) }
        } else {
            updateStatus { $0.noteEventMissing(name) }
        }
    }
}
