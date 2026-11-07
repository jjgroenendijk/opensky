// The movement type an actor's graph state names, which sets its speeds
// (docs/engine/actor-state-graph.md#how-the-game-picks-istate).

import OpenSkyBehavior
public import OpenSkyFormatsESM
import OpenSkyGameData

extension ActorGraphCoordinator {
    /// The name after `iState_` of the actor's current state, such as `HorseDefault`; nil
    /// without a running graph or a constant for the value.
    public func movementStateName(of actor: ReferenceKey) -> String? {
        guard
            let entry = running[actor],
            let state = entry.instance.variable(named: ActorGraphNames.state)
        else { return nil }
        return entry.stateNames[Int32(truncatingIfNeeded: state.intValue)]
    }
}

nonisolated extension ActorGraphCore {
    static let statePrefix = "iState_"

    /// Each `iState_*` constant's value and its name without the prefix. The first
    /// constant of a value wins.
    static func stateNames(of instance: BehaviorGraphInstance) -> [Int32: String] {
        var names: [Int32: String] = [:]
        for case let name? in instance.variables.names where name.hasPrefix(statePrefix) {
            guard let value = instance.variable(named: name) else { continue }
            let key = Int32(truncatingIfNeeded: value.intValue)
            if names[key] == nil {
                names[key] = String(name.dropFirst(statePrefix.count))
            }
        }
        return names
    }
}
