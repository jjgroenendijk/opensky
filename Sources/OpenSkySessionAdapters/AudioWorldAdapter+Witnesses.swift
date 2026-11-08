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
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Witnesses that forward to the narrow parts of `AudioWorldAdapter`.
extension AudioWorldAdapter {
    public var audioListenerPose: (position: SIMD3<Float>, yaw: Float) {
        listener.audioListenerPose
    }

    public var playerFeetArmatures: [FormID]? {
        listener.playerFeetArmatures
    }

    public var playerGait: LocomotionGait? {
        listener.playerGait
    }

    public var playerFeetPosition: SIMD3<Float>? {
        listener.playerFeetPosition
    }

    public var audioAnimationTime: Float {
        listener.audioAnimationTime
    }

    public func lipSyncTarget() -> LipSyncPlayback? {
        listener.lipSyncTarget()
    }

    public func lipSyncTarget(for speaker: ReferenceKey) -> LipSyncPlayback? {
        listener.lipSyncTarget(for: speaker)
    }

    public func speakerHeadPosition(of speaker: ReferenceKey) -> SIMD3<Float>? {
        listener.speakerHeadPosition(of: speaker)
    }

    public func isConversationSpeaker(_ speaker: ReferenceKey) -> Bool {
        mix.isConversationSpeaker(speaker)
    }

    public func playerConditionsPass(_ conditions: [Condition]) -> Bool {
        mix.playerConditionsPass(conditions)
    }
}
