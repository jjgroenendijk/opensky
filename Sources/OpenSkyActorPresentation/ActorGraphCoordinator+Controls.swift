// The persisted settings of `ActorGraphCoordinator`, and the inputs of one step.

import OpenSkyGameData

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
            -ActorGraphCore.turnDelta(from: $0, to: candidate.rotationZ)
        } ?? 0
        lastFeet = candidate.feet
        lastRotation = candidate.rotationZ
        return ActorGraphStepInput(
            motion: next, speed: gait.speed, turnDelta: turn, deltaTime: seconds
        )
    }
}
