// The persisted settings of `ActorGraphCoordinator`, the inputs of one step, and the
// `iState` a step writes back when the drunk tag changes.

import OpenSkyBehavior
public import OpenSkyGameData
import OpenSkyWorldInterface

extension ActorGraphCoordinator {
    /// Reads the switch and the cutoff from `store`.
    public func load(settings store: PlayerSettingsStore) {
        isEnabled = store.bool(.actorGraphs)
        cutoff = ActorGraphCutoff(
            fullRateDistance: Float(store.value(.actorGraphFullRateDistance)),
            maximumDistance: Float(store.value(.actorGraphDistance))
        )
    }
}

extension ActorGraphCoordinator.Running {
    /// This step's locomotion inputs. Measures the travel since the last step, and queues
    /// the events of any change in the motion the graph is shown.
    func stepInput(for candidate: ActorGraphCandidate, seconds: Float) -> ActorGraphStepInput {
        let measured = lastFeet.map {
            ActorGraphCore.speed(from: $0, to: candidate.feet, seconds: seconds)
        } ?? 0
        gait.sample(measured, seconds: seconds, isDriven: motion.isMoving)
        let next = gait.shown(motion)
        pendingEvents += ActorGraphCore.events(from: shown, to: next)
        shown = next
        let turn = lastRotation.map {
            // Placement rotation turns clockwise; the graph's turn is counter-clockwise.
            ActorGraphCore.turnRate(
                radians: -ActorGraphCore.turnDelta(from: $0, to: candidate.rotationZ),
                seconds: seconds
            )
        } ?? 0
        lastFeet = candidate.feet
        lastRotation = candidate.rotationZ
        var input = ActorGraphStepInput(
            motion: next, speed: gait.speed / max(candidate.scale, 0.01), turnDelta: turn,
            deltaTime: seconds
        )
        input.weight = candidate.weight
        return input
    }
}

extension ActorGraphCoordinator.Running {
    /// Writes the step's state tag into `iState`, which picks the speed sampler's table
    /// (docs/engine/actor-state-graph.md).
    func noteStateTag() {
        isDrunk = instance.isTaggingState(ActorGraphNames.drunkState)
        guard
            let value = ActorGraphCore.state(tag: instance.stateTag?.value, rest: restState),
            instance.variable(named: ActorGraphNames.state) != .int(value)
        else { return }
        instance.setVariable(.int(value), named: ActorGraphNames.state)
    }
}
