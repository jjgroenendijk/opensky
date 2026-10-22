// App side of `DialogueCoordinator`: wires the dialogue index and the Talk
// seams onto the streamer, and answers `DialogueWorld` from the session
// systems. The rules live in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyDiagnostics
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `DialogueWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol DialogueWorldHost: AnyObject {
    var actorWorld: ActorWorldAdapter { get }
    var containerMenu: ContainerMenuController { get }
    func animatedPose(for key: ReferenceKey) -> [String: float4x4]?
    var dialogue: DialogueCoordinator { get }
    var dialogueCamera: DialogueCameraController { get }
    var dialogueMenu: DialogueMenuController { get }
    var faceMorphs: FaceMorphCoordinator { get }
    var factions: FactionCoordinator { get }
    var headTracking: HeadTrackingCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var localizedStringsLoader: (() -> LocalizedStrings)? { get }
    var mapWorld: MapWorldAdapter { get }
    var packages: PackageCoordinator { get }
    var perks: PerkCoordinator { get }
    var player: PlayerCoordinator { get }
    var progression: ProgressionCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var runtimeState: RuntimeStateCoordinator { get }
    var scripts: ScriptCoordinator { get }
    var storyWorld: StoryWorldAdapter { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
}

/// Answers `DialogueWorld` from the session systems `game` owns.
final class DialogueWorldAdapter {
    unowned let game: any DialogueWorldHost
    /// `VTCK` by actor base. A template walk per actor per condition context costs too much.
    private var voiceTypesByBase: [FormID: FormID?] = [:]

    init(game: any DialogueWorldHost) {
        self.game = game
    }

    /// Hostility and death decide who is worth talking to, so the candidate
    /// list is built here, not in streaming.
    func wireDialogue(provider: WorldDataStores, streamer: CellStreamer) {
        game.dialogue.index = provider.dialogueStore
        game.dialogue.topicSubtypes = TopicSubtypeTexts
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        game.dialogue.speechTimers = SpeechTimerSettings.resolve(store: provider.gameSettings)
        game.headTracking.settings = HeadTrackingSettings.resolve(store: provider.gameSettings)
        game.faceMorphs.settings = FaceAnimationSettings.resolve(store: provider.gameSettings)
        streamer.talk.candidateSource = { [weak self] in
            self?.talkCandidates() ?? []
        }
        // Activating a living actor while sneaking opens its pockets instead of a talk.
        streamer.talk.activations.add { [weak self] event in
            guard let game = self?.game else { return }
            if game.player.isSneaking, game.containerMenu.openPickpocket(of: event.speaker) {
                return
            }
            game.dialogueMenu.begin(with: event.speaker)
        }
    }

    /// Runs after the actor systems in the world tick, so the camera reads
    /// this frame's pose.
    func wireDialogueCamera(gameSession: GameSession) {
        let renderer = gameSession.renderer
        gameSession.worldTick.register(.dialogueCamera) { [weak self] delta in
            self?.game.dialogueCamera.refreshFocus()
            self?.game.faceMorphs.tick(now: self?.game.renderer?.animationTime ?? 0)
            self?.game.headTracking.tick(deltaTime: delta)
        }
        renderer.worldOverlaySources
            .register(identifier: "dialogue-camera") { [weak gameSession] context, list in
                gameSession?.appendDialogueCameraOverlay(context: context, to: &list)
            }
    }

    /// Dead and hostile actors are left out. An actor with no passing topic
    /// still opens an empty menu, so the condition trace can explain why.
    func talkCandidates() -> [TalkCandidate] {
        guard let streamer = game.streamer else { return [] }
        return game.actorWorld.combatActors().compactMap { observation in
            guard
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
                name: speakerName(entry: entry, fallback: observation.name)
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
    func speakerLabel(for speaker: ReferenceKey) -> String {
        guard let entry = game.streamer?.referenceEntry(key: speaker) else {
            return speaker.description
        }
        if let name = game.streamer?.interactionName(reference: entry.formID), !name.isEmpty {
            return name
        }
        return entry.placedActor.flatMap { game.actorWorld.displayName(base: $0.base) }
            ?? speaker.description
    }

    /// The voice type of each loaded actor, for `GetIsVoiceType` and voice file paths.
    func residentVoiceTypes() -> [ReferenceKey: FormID] {
        guard
            let entries = game.streamer?.residentActorEntries(),
            let resolver = game.worldData?
                .actorValueBaselines?.resolver
        else { return [:] }
        let records = ActorIdentityRecords(resolver: resolver)
        var voices: [ReferenceKey: FormID] = [:]
        for entry in entries {
            guard let base = entry.placedActor?.base else { continue }
            let voice = voiceTypesByBase[base] ?? records.voiceType(ofBase: base)
            voiceTypesByBase[base] = voice
            voices[entry.key] = voice
        }
        return voices
    }

    /// The posed `NPC Head [Head]` bone, or the capsule eye height when the
    /// actor has no rig.
    func headPosition(of actor: ReferenceKey) -> SIMD3<Float>? {
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

extension DialogueWorldAdapter: DialogueWorld {
    func questStates() -> QuestResolution? {
        game.scripts.bridge?.questRuntime?.resolution()
    }

    func questAliases() -> QuestAliasResolution {
        game.scripts.bridge?.questRuntime?.aliasResolution() ?? .empty
    }

    func conditionContext() -> ConditionContext {
        var context = game.runtimeState.conditionContext()
        context.dialogue = DialogueResolution(
            voiceTypes: residentVoiceTypes(),
            speakerInDialogue: context.dialogue.speakerInDialogue,
            line: context.dialogue.line
        )
        context.speechChecks = speechCheckResolution()
        return context
    }

    /// The perk factors are for the actor the player talks to.
    private func speechCheckResolution() -> SpeechCheckResolution {
        let speaker = game.dialogue.conversationSpeaker
        let gold = game.inventory.runtime.map { runtime in
            Int(runtime.inventory.count(of: runtime.inventory.goldFormID, in: runtime.player))
        }
        return SpeechCheckResolution(
            settings: game.worldData?.speechCheckSettings,
            playerGold: gold,
            intimidationFactor: game.perks.multiplier(
                at: .modPlayerIntimidation, on: .player, target: speaker
            ),
            bribeFactor: game.perks.multiplier(at: .modBribeAmount, on: .player, target: speaker)
        )
    }

    var conditionRegistry: ConditionFunctionRegistry {
        .standard
    }

    var fragments: (any DialogueFragmentDispatching)? {
        game.scripts.bridge
    }

    func loadStrings() -> LocalizedStrings? {
        game.localizedStringsLoader?()
    }

    func run(_ commands: [DialogueCommand]) {
        for command in commands {
            switch command {
            case let .suspendPackage(actor): game.packages.suspend(actor)
            case let .resumePackage(actor): game.packages.resume(actor)
            case let .stopActor(actor): game.streamer?.stopActor(actor)
            case let .faceActor(actor, point): game.streamer?.faceActor(actor, towards: point)
            case let .releaseFacing(actor): game.streamer?.releaseActorFacing(actor)
            case let .speechChallengeWon(challenge, speaker):
                speechChallengeWon(challenge, speaker: speaker)
            case let .spokeToPlayer(speaker): spokeToPlayer(speaker)
            }
        }
    }

    /// `BRIB`, `INTM`, or `FLAT`, with the actor the player won over as `R1`.
    private func speechChallengeWon(_ challenge: SpeechChallenge, speaker: ReferenceKey) {
        var event = StoryEventData(event: FourCC(stringLiteral: challenge.eventCode))
        event.actor1 = speaker
        game.storyWorld.reportStoryEvent(event)
        game.worldState.incrementMiscStat(challenge.statName)
        game.progression.reportSpeechCheckWon()
    }

    private func spokeToPlayer(_ speaker: ReferenceKey) {
        game.scripts.bridge?.updateScriptedState(of: speaker) {
            $0.setFlag(ScriptedStateName.talkedToPlayer, true)
        }
    }
}
