public import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyEffects
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyMenus
import OpenSkyMenusInterface
public import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `AudioListenerAdapter` reads from the session.
@MainActor
public protocol AudioListenerHost: AnyObject {
    var dialogueMenu: any DialogueMenuPort { get }
    var dialogueWorld: any DialogueWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var renderer: (any RendererPort)? { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `AudioWorldAdapter`, over its own narrow host.
public struct AudioListenerAdapter {
    public unowned let game: any AudioListenerHost
}

extension AudioListenerAdapter {
    public var audioListenerPose: (position: SIMD3<Float>, yaw: Float) {
        let camera = game.gameSession?.freeFlyCamera
        return (camera?.position ?? .zero, camera?.yaw ?? 0)
    }

    public var playerFeetArmatures: [FormID]? {
        game.gameSession?.playerBody?.feetArmatures
    }

    public var playerGait: LocomotionGait? {
        game.gameSession?.locomotion.status.gait
    }

    public var playerFeetPosition: SIMD3<Float>? {
        game.gameSession?.walkController.feetPosition
    }

    public var audioAnimationTime: Float {
        game.renderer?.animationTime ?? 0
    }

    public func lipSyncTarget() -> LipSyncPlayback? {
        game.dialogueMenu.speakerOrTarget.flatMap(lipSyncTarget(for:))
    }

    public func lipSyncTarget(for speaker: ReferenceKey) -> LipSyncPlayback? {
        guard
            let renderer = game.renderer,
            let actor = game.streamer?.referenceEntry(key: speaker)?.placedActor?.formID
        else { return nil }
        return renderer.scene.animations.lazy
            .compactMap { $0 as? LipSyncPlayback }
            .first { $0.actor == actor }
    }

    public func speakerHeadPosition(of speaker: ReferenceKey) -> SIMD3<Float>? {
        game.dialogueWorld.headPosition(of: speaker)
    }
}
