public import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkySession
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `PlayerFaceAdapter` reads from the session.
@MainActor
public protocol PlayerFaceHost: AnyObject {
    var actorValues: any ActorValuePort { get }
    var actorWorld: any ActorWorldPort { get }
    var combat: any CombatPort { get }
    var dialogueMenu: any DialogueMenuPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var renderer: (any RendererPort)? { get }
    var streamer: (any CellStreamerPort)? { get }
}

/// Part of `PlayerWorldAdapter`, over its own narrow host.
public struct PlayerFaceAdapter {
    public unowned let owner: PlayerWorldAdapter
    public unowned let game: any PlayerFaceHost
}

extension PlayerFaceAdapter {
    public var faceMorphSubject: FormID? {
        guard let key = game.dialogueMenu.speakerOrTarget else { return nil }
        return game.streamer?.referenceEntry(key: key)?.placedActor?.formID
    }

    public func faceMorphPlayback(for actor: FormID) -> FaceMorphPlayback? {
        if actor == PlayerBody.actorFormID {
            return owner.playerFace()
        }
        return game.renderer?.scene.faceMorphPlayback(for: actor)
    }

    public var faceMorphPlaybacks: [FaceMorphPlayback] {
        let scene = game.renderer?.scene.animations.compactMap { $0 as? FaceMorphPlayback }
        return (scene ?? []) + [owner.playerFace()].compactMap(\.self)
    }

    public func faceMood(of actor: FormID) -> FaceMoodInput {
        let key = actor == PlayerBody.actorFormID
            ? ReferenceKey.player : game.streamer?.referenceEntry(formID: actor)?.key
        guard let key else { return .calm }
        let facts = key == .player
            ? game.combat.playerActionFacts : game.combat.loop?.phase(of: key)?.actionFacts
        let mood = game.actorWorld.actorValueHolder(for: key).flatMap { holder in
            game.actorValues.runtime?.value(at: Self.moodActorValue, on: holder)
        }
        // The player's face reads only its own draw and swing, an NPC's its combat.
        let swings = [ActorAttackState.draw, .swing].contains(facts?.attackState ?? .none)
        return FaceMoodInput(
            isFleeing: facts?.isFleeing == true,
            isInCombat: key != .player && game.actorWorld.isInCombat(key),
            isAttacking: key == .player && swings,
            mood: mood.map { Int($0) } ?? 0
        )
    }

    /// `Mood`, actor value 4.
    private static let moodActorValue: Int32 = 4

    public var headTrackingSubjects: [HeadTrackingSubject] {
        guard
            let renderer = game.renderer, let gameSession = game.gameSession,
            let streamer = game.streamer else { return [] }
        let deltas = gameSession.instancePoses.npcDeltas
        return game.actorWorld.combatActors().compactMap { actor in
            guard
                !actor.isDead,
                let formID = streamer.referenceEntry(key: actor.key)?.placedActor?.formID,
                let playback = renderer.scene.actorPlayback(for: formID)
            else { return nil }
            let delta = deltas[formID.rawValue] ?? matrix_identity_float4x4
            return HeadTrackingSubject(
                key: actor.key, playback: playback, worldFromActor: delta * playback.transform
            )
        }
    }

    public func headPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        if key == .player {
            return game.gameSession.map {
                $0.walkController.feetPosition + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight)
            }
        }
        guard let actor = game.actorWorld.combatActor(key: key) else {
            return nil
        }
        return actor.feet + SIMD3(0, 0, actor.capsule.eyeHeight * max(actor.scale, 0))
    }
}
