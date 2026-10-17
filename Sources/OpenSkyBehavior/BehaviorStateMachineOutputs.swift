// What a state machine publishes to graph variables: `m_isActive` and `m_currentStateId`
// through output bindings, and its current state through `m_syncVariableIndex`. The
// vanilla graphs read `bAnimationDriven`, `IsEquipping`, `iBlockState`, and the `iSync*`
// variables this way (docs/engine/behavior-state-machines.md).

import Foundation
import OpenSkyFormatsAnimation

nonisolated extension BehaviorGraphInstance {
    /// Publishes a running machine's outputs and its sync variable.
    func publishMachineOutputs(
        _ machine: HKBStateMachine,
        at target: HKXPointerTarget,
        currentStateId: Int
    ) {
        if let node = compiledNode(at: target) {
            writeOutputs(
                [
                    "isActive": .bool(true),
                    "currentStateId": .int(Int32(truncatingIfNeeded: currentStateId))
                ],
                of: node
            )
        }
        if machine.syncVariableIndex >= 0 {
            writeVariable(
                .int(Int32(truncatingIfNeeded: currentStateId)), at: machine.syncVariableIndex
            )
        }
    }

    /// A machine that stopped running reads inactive, unless a node that just became
    /// active wrote the same variable this update.
    func publishMachineDeactivation(at target: HKXPointerTarget) {
        guard let node = compiledNode(at: target) else { return }
        let fresh = outputIndexes(of: node, path: "isActive").allSatisfy {
            !variablesWrittenThisUpdate.contains($0)
        }
        guard fresh else { return }
        writeOutputs(["isActive": .bool(false)], of: node)
    }
}
