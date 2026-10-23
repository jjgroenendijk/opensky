// Actor state readout: the inputs the engine wrote and the
// outputs the graph published, as the third-person graph holds them now. No AppKit
// import: the CLI builds it too.

import Foundation
import OpenSkyBehavior

/// The actor-state variables for one refresh.
nonisolated public struct ActorStateGraphSnapshot: Equatable, Sendable {
    public let inputs: [LocomotionVariableSnapshot]
    public let outputs: [LocomotionVariableSnapshot]
    /// `iState` with the constant that holds its value, or nil without a graph.
    public let state: String?

    public static let empty = ActorStateGraphSnapshot(inputs: [], outputs: [], state: nil)

    public init(
        inputs: [LocomotionVariableSnapshot],
        outputs: [LocomotionVariableSnapshot],
        state: String?
    ) {
        self.inputs = inputs
        self.outputs = outputs
        self.state = state
    }

    /// Reads every input and output off `graph`. A name the graph does not declare
    /// gets a nil value, so a mismatch shows on the readout.
    public static func read(
        _ graph: BehaviorGraphInstance?, constants: [ActorGraphState: Int32]
    ) -> ActorStateGraphSnapshot {
        guard let graph else { return .empty }
        func snapshot(_ name: String) -> LocomotionVariableSnapshot {
            LocomotionVariableSnapshot(
                name: name, value: graph.variable(named: name).map(PlayerCore.describe)
            )
        }
        let state = graph.variable(named: ActorStateGraphNames.state).map {
            ActorStateGraphCore.stateName(
                of: Int32(truncatingIfNeeded: $0.intValue), constants: constants
            )
        }
        return ActorStateGraphSnapshot(
            inputs: ActorStateGraphNames.inputs.map(snapshot),
            outputs: ActorStateGraphNames.outputs.map(snapshot),
            state: state
        )
    }
}
