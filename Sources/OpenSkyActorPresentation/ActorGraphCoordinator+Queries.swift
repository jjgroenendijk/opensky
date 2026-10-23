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

    /// Hands the actor's graph to the player's mount drive, which steps it until
    /// `giveBack`. Nil when the actor runs no graph.
    public func lend(_ actor: ReferenceKey) -> ActorGraphLoan? {
        guard let entry = running[actor] else { return nil }
        entry.isLent = true
        return ActorGraphLoan(instance: entry.instance, pose: entry.pose)
    }

    /// The coordinator steps the graph again, from the actor's drive.
    public func giveBack(_ actor: ReferenceKey) {
        guard let entry = running[actor], entry.isLent else { return }
        entry.isLent = false
        entry.lastFeet = nil
        entry.lastRotation = nil
        // The ridden graph may be left moving: stop events return it to the drive's state.
        let lent = ActorGraphMotion(isMoving: true, isSprinting: true, isInCombatStance: true)
        entry.motion = motions[actor] ?? .still
        entry.pendingEvents += ActorGraphCore.events(from: lent, to: entry.motion)
    }
}

/// A graph lent to the player's mount drive, and the pose buffer its playback draws.
public struct ActorGraphLoan {
    public let instance: BehaviorGraphInstance
    public let pose: PlayerPoseBuffer
}
