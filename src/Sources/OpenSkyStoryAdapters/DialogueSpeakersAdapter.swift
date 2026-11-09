import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
public import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyPhysics
public import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// What `DialogueSpeakersAdapter` reads from the session.
@MainActor
public protocol DialogueSpeakersHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]?
    var factions: any FactionPort { get }
    var mountWorld: any MountWorldPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `DialogueWorldAdapter`, over its own narrow host.
public struct DialogueSpeakersAdapter {
    public let game: any DialogueSpeakersHost
    public let voiceTypes: DialogueVoiceTypeCache
}

extension DialogueSpeakersAdapter {
    /// Dead and hostile actors are left out, and so are actors `ray` cannot reach. An actor
    /// with no passing topic still opens an empty menu, so the condition trace can explain why.
    public func talkCandidates(along ray: InteractionRay) -> [TalkCandidate] {
        guard let streamer = game.streamer else { return [] }
        return game.actorWorld.combatActors().compactMap { observation in
            guard
                TalkTargetPicker.mayReach(observation.feet, along: ray),
                !observation.isDead,
                game.factions.hostility(of: observation.key) != .hostile,
                let entry = streamer.referenceEntry(key: observation.key),
                let actor = entry.placedActor
            else {
                return nil
            }
            return TalkCandidate(
                key: observation.key,
                reference: entry.formID,
                base: actor.base,
                feet: observation.feet,
                name: speakerName(entry: entry, fallback: observation.name),
                actionLabel: game.mountWorld.promptLabel(for: observation.key)
            )
        }
    }

    private func speakerName(entry: RuntimeReferenceEntry, fallback: String) -> String {
        if let name = game.streamer?.interactionName(reference: entry.formID), !name.isEmpty {
            return name
        }
        return fallback.isEmpty ? entry.key.description : fallback
    }

    /// The same resolved name the crosshair prompt uses, so the prompt and the
    /// menu header agree.
    public func speakerLabel(for speaker: ReferenceKey) -> String {
        guard let entry = game.streamer?.referenceEntry(key: speaker) else {
            return speaker.description
        }
        if let name = game.streamer?.interactionName(reference: entry.formID), !name.isEmpty {
            return name
        }
        return entry.placedActor.flatMap { game.actorWorld.displayName(of: speaker, base: $0.base) }
            ?? speaker.description
    }

    /// The voice type of each loaded actor, for `GetIsVoiceType` and voice file paths.
    public func residentVoiceTypes() -> [ReferenceKey: FormID] {
        guard
            let entries = game.streamer?.residentActorEntries(),
            let resolver = game.worldData?
                .actorValueBaselines?.resolver
        else { return [:] }
        let records = ActorIdentityRecords(resolver: resolver)
        var voices: [ReferenceKey: FormID] = [:]
        for entry in entries {
            guard let base = entry.placedActor?.base else { continue }
            let roll = game.worldState.leveledRoll(
                of: entry.key, base: base, with: records.templates.leveling
            )
            let key = LeveledActorRollKey(base: base, roll: roll)
            let voice = voiceTypes.byRoll[key] ?? records.voiceType(ofBase: base, roll: roll)
            voiceTypes.byRoll[key] = voice
            voices[entry.key] = voice
        }
        return voices
    }

    /// The posed `NPC Head [Head]` bone, or the capsule eye height when the
    /// actor has no rig.
    public func headPosition(of actor: ReferenceKey) -> SIMD3<Float>? {
        guard
            let streamer = game.streamer,
            let entry = streamer.referenceEntry(key: actor),
            let placed = entry.placedActor
        else { return nil }
        let override = streamer.npcTransform(for: actor)
        let feet = override?.position ?? placed.placement.position
        guard
            let pose = game.animatedPose(for: actor),
            let head = pose[DialogueCamera.headBoneName]
        else {
            return feet + SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight)
        }
        let actorToWorld = MatrixMath.placement(
            position: feet,
            rotation: override?.rotation ?? placed.placement.rotation,
            scale: override?.scale ?? placed.scale
        )
        let world = actorToWorld * head
        return SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    }
}
