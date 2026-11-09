// App side of `AnimationEventCoordinator`: where a source stands, and the sound, camera,
// and head tracking systems its annotations reach (docs/engine/animation-events.md).

public import OpenSkyActorPresentation
import OpenSkyCamera
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyObjectAnimation
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// What `AnimationEventWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol AnimationEventWorldHost: AnyObject {
    var objectBehaviors: any ObjectBehaviorPort { get }
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]?
    var cinematicCamera: any CinematicCameraPort { get }
    var headTracking: any HeadTrackingPort { get }
    var effectGraphs: any EffectGraphPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var idleWorld: any IdleWorldPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
}

public final class AnimationEventWorldAdapter {
    public let game: any AnimationEventWorldHost

    public init(game: any AnimationEventWorldHost) {
        self.game = game
    }
}

extension AnimationEventWorldAdapter: AnimationEventWorld {
    public func animationEventPosition(of source: ReferenceKey) -> SIMD3<Float>? {
        guard let gameSession = game.gameSession else { return nil }
        if source == .player {
            return gameSession.locomotion.status.feetPosition
        }
        let streamer = game.streamer
        if let moved = streamer.npcTransform(for: source) {
            return moved.placement.position
        }
        let entry = streamer.referenceEntry(key: source)
        return entry?.placedActor?.placement.position ?? entry?.placedReference?.placement.position
    }

    public func playAnimationSound(
        editorID: String, source: ReferenceKey, at position: SIMD3<Float>
    ) -> Bool {
        guard let director = game.gameSession?.soundDirector else { return true }
        return director.playAnimationSound(editorID: editorID, source: source, at: position)
    }

    public func stopAnimationSound(editorID: String, source: ReferenceKey) {
        game.gameSession?.soundDirector?.stopAnimationSound(editorID: editorID, source: source)
    }

    public func releaseAnimationSound(editorID: String, source: ReferenceKey) {
        game.gameSession?.soundDirector?.releaseAnimationSound(editorID: editorID, source: source)
    }

    public func shakeCamera(from position: SIMD3<Float>, strength: Float) {
        game.cinematicCamera.startShake(
            source: position, strength: strength, duration: Float(CameraShake.defaultDuration)
        )
    }

    public func setHeadTracking(_ enabled: Bool, for actor: ReferenceKey) {
        game.headTracking.setHeadTracking(enabled, for: actor)
    }

    public func sendScriptAnimationEvent(_ name: String, from source: ReferenceKey) {
        game.scripts.runtime?.queueAnimationEvent(sender: source, name: name)
    }

    public func sendEffectGraphEvent(_ name: String, from source: ReferenceKey) {
        game.effectGraphs.deliver(name, from: source)
    }
}
