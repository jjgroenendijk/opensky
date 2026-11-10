import Foundation
import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEffects
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenusInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkyRenderResources
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// What `EffectsEffectPlacementAdapter` reads from the session.
@MainActor
public protocol EffectsEffectPlacementHost: AnyObject, SendableMetatype {
    var combat: any CombatPort { get }
    func actorPlayback(for key: ReferenceKey) -> (any ActorAnimationPlaybackPort)?
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var audio: any AudioPort { get }
    var effects: any EffectsPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var renderer: (any RendererPort)? { get }
    var scripts: any ScriptPort { get }
}

/// Part of `EffectsWorldAdapter`, over its own narrow host.
public struct EffectsEffectPlacementAdapter {
    public let game: any EffectsEffectPlacementHost
    public let state: EffectsPartState
}

extension EffectsEffectPlacementAdapter {
    var effectCamera: VisualEffectRuntime.CameraPose? {
        game.renderer.map { .init(eye: $0.camera.eye, target: $0.camera.target) }
    }

    /// An actor's feet turned to its facing; the player's turn with the camera.
    public func effectTransform(of actor: ReferenceKey) -> float4x4? {
        if actor == .player {
            guard
                let renderer = game.renderer,
                let gameSession = game.gameSession else { return nil }
            let look = renderer.camera.target - renderer.camera.eye
            return Self.transform(
                feet: gameSession.locomotion.status.feetPosition,
                yaw: atan2(look.y, look.x)
            )
        }
        guard let observed = game.actorWorld.combatActor(key: actor) else {
            // A script plays effects on objects too; they stand where their record and
            // the session's moves put them.
            return game.scripts.bridge?.referenceState(for: actor).map {
                MatrixMath.placement(
                    position: $0.transform.position, rotation: $0.transform.rotation, scale: 1
                )
            }
        }
        return Self.transform(feet: observed.feet, yaw: observed.facing)
    }

    /// The pose in model space, placed where the actor's reference stands, as a script's
    /// node lookup places it.
    public func effectBones(of actor: ReferenceKey) -> [String: float4x4] {
        guard
            let renderer = game.renderer, let playback = game.actorPlayback(for: actor),
            let pose = playback.skeletonPose(at: renderer.animationTime),
            let state = game.scripts.bridge?.referenceState(for: actor)
        else { return [:] }
        let toWorld = MatrixMath.placement(
            position: state.transform.position, rotation: state.transform.rotation,
            scale: state.transform.scale
        )
        return pose.named.mapValues { toWorld * $0 }
    }

    public func membraneTarget(of actor: ReferenceKey) -> MembraneTarget? {
        switch actor {
        case .player: .player
        case let .plugin(_, objectID): .actor(objectID)
        default: nil
        }
    }

    public func detonateEffectExplosion(_ explosion: ReferenceKey, at position: SIMD3<Float>) {
        guard let spec = game.combat.explosions.spec(for: explosion) else { return }
        game.combat.explosions.detonate(spec, at: position, cause: .spell)
    }

    private static func transform(feet: SIMD3<Float>, yaw: Float) -> float4x4 {
        var matrix = float4x4(simd_quatf(angle: yaw, axis: SIMD3(0, 0, 1)))
        matrix.columns.3 = SIMD4(feet, 1)
        return matrix
    }

    /// A load stops the heartbeat at once and forgets the last health, as the game does.
    public func resetHealthCues() {
        game.audio.soundDirector?.stopScriptSound(state.heartbeatSound)
        state.heartbeatSound = 0
        game.effects.resetHealthCues()
    }

    /// A new game fades the heartbeat out, as the game does on a start.
    public func fadeOutHealthCues() {
        game.audio.soundDirector?.fadeOutScriptSound(
            state.heartbeatSound, seconds: PlayerHealthCues.heartbeatFadeSeconds
        )
        state.heartbeatSound = 0
        game.effects.resetHealthCues()
    }

    func stepHealthCues(_ seconds: Float, gameSession: GameSession) {
        guard let values = game.actorValues.runtime else { return }
        let director = game.audio.soundDirector
        let share = PlayerHealthCues.share(
            current: values.current(of: .player).health,
            maximum: values.permanentMaximum(of: .health, for: .player)
        )
        let playing = state.heartbeatSound != 0 && director?
            .isScriptSoundPlaying(state.heartbeatSound) == true
        let change = game.effects.stepHealthCues(
            share: share, seconds: seconds, heartbeatPlaying: playing,
            imageSpace: &gameSession.imageSpace
        )
        guard let change, let director else { return }
        switch change {
        case let .start(heartbeat):
            director.stopScriptSound(state.heartbeatSound)
            state.heartbeatSound = 0
            guard let sound = game.effects.heartbeatSound(heartbeat) else { return }
            state.heartbeatSound = director.playScriptSound(
                formID: sound, at: state.cameraPosition ?? .zero
            )
        case .fadeOut:
            director.fadeOutScriptSound(
                state.heartbeatSound, seconds: PlayerHealthCues.heartbeatFadeSeconds
            )
            state.heartbeatSound = 0
        }
    }
}
