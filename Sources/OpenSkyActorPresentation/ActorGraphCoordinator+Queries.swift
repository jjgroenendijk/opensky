// What the drive, Papyrus, and the conditions ask of a running actor graph.

import OpenSkyBehavior
import OpenSkyConditions
import OpenSkyFormatsESM

extension ActorGraphCoordinator {
    /// The drive's locomotion state. A change raises its events on the next step.
    public func setMotion(_ motion: ActorGraphMotion, for actor: ReferenceKey) {
        let previous = motions[actor] ?? .still
        motions[actor] = motion
        guard let entry = running[actor] else { return }
        entry.pendingEvents += ActorGraphCore.events(from: previous, to: motion)
        entry.motion = motion
    }

    /// Raises `event` on the actor's graph. False when it runs none or lacks the event.
    @discardableResult
    public func raise(_ event: String, on actor: ReferenceKey) -> Bool {
        running[actor]?.instance.raiseEvent(named: event) ?? false
    }

    public func isRunning(_ actor: ReferenceKey) -> Bool {
        running[actor] != nil
    }

    public func variable(named name: String, on actor: ReferenceKey) -> BehaviorVariableValue? {
        running[actor]?.instance.variable(named: name)
    }

    @discardableResult
    public func setVariable(
        _ value: BehaviorVariableValue, named name: String, on actor: ReferenceKey
    ) -> Bool {
        running[actor]?.instance.setVariable(value, named: name) ?? false
    }

    /// Every running graph's variables, and the player's, for the condition functions.
    public func variableResolution(player: BehaviorVariableStore?) -> GraphVariableResolution {
        var graphs: [ReferenceKey: any GraphVariableReading] = running.mapValues {
            ActorGraphVariables(store: $0.instance.variables)
        }
        graphs[.player] = player.map(ActorGraphVariables.init(store:))
        return GraphVariableResolution(graphs: graphs)
    }
}
