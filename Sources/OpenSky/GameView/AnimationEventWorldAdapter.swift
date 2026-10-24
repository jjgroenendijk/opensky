// App side of `AnimationEventCoordinator`: where a source stands, and the sound, camera,
// and head tracking systems its annotations reach (docs/engine/animation-events.md).

import OpenSkyActorPresentation
import OpenSkyCamera
import OpenSkyFormatsESM
import OpenSkyPlayer
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState
import simd

/// What `AnimationEventWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol AnimationEventWorldHost: AnyObject {
    var cinematicCamera: CinematicCameraCoordinator { get }
    var headTracking: HeadTrackingCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var scripts: ScriptCoordinator { get }
    var streamer: CellStreamer? { get }
}

final class AnimationEventWorldAdapter {
    unowned let game: any AnimationEventWorldHost

    init(game: any AnimationEventWorldHost) {
        self.game = game
    }

    /// The player graph's events, read once per frame. The idle and object graph
    /// callbacks send theirs to the coordinator directly.
    func wire(gameSession: GameSession) {
        let events = AnimationEventCoordinator(world: self)
        gameSession.animationEvents = events
        gameSession.frameSteps.register(.animationEvents) { [weak gameSession, weak events] _ in
            guard let gameSession else { return }
            let locomotion = gameSession.locomotion
            let names = locomotion.graphEvents.drain(locomotion.animationEventConsumer)
            guard gameSession.movementMode.isPlayerControlled else { return }
            for name in names {
                events?.handle(name, from: .player)
            }
        }
    }
}

extension AnimationEventWorldAdapter: AnimationEventWorld {
    func animationEventPosition(of source: ReferenceKey) -> SIMD3<Float>? {
        guard let gameSession = game.gameSession else { return nil }
        if source == .player {
            return gameSession.locomotion.status.feetPosition
        }
        guard let streamer = game.streamer else { return nil }
        if let moved = streamer.npcTransform(for: source) {
            return moved.placement.position
        }
        let entry = streamer.referenceEntry(key: source)
        return entry?.placedActor?.placement.position ?? entry?.placedReference?.placement.position
    }

    func playAnimationSound(
        editorID: String, source: ReferenceKey, at position: SIMD3<Float>
    ) -> Bool {
        guard let director = game.gameSession?.soundDirector else { return true }
        return director.playAnimationSound(editorID: editorID, source: source, at: position)
    }

    func stopAnimationSound(editorID: String, source: ReferenceKey) {
        game.gameSession?.soundDirector?.stopAnimationSound(editorID: editorID, source: source)
    }

    func shakeCamera(from position: SIMD3<Float>, strength: Float) {
        game.cinematicCamera.startShake(
            source: position, strength: strength, duration: Float(CameraShake.defaultDuration)
        )
    }

    func setHeadTracking(_ enabled: Bool, for actor: ReferenceKey) {
        game.headTracking.setHeadTracking(enabled, for: actor)
    }

    func sendScriptAnimationEvent(_ name: String, from source: ReferenceKey) {
        game.scripts.runtime?.queueAnimationEvent(sender: source, name: name)
    }
}
