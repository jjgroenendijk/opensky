// App side of `CombatCoordinator`: builds its runtimes from the provider, steps
// them from the renderer's frame hooks, and plays reaction clips. The rules live
// in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyBehavior
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState

/// What `CombatWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol CombatWorldHost: AnyObject {
    func actorPlayback(for key: ReferenceKey) -> ActorAnimationPlayback?
    var actorValues: ActorValueCoordinator { get }
    var actorWorld: ActorWorldAdapter { get }
    var audio: AudioCoordinator { get }
    var combat: CombatCoordinator { get }
    var crime: CrimeCoordinator { get }
    var dialogue: DialogueCoordinator { get }
    var effects: EffectsCoordinator { get }
    var factions: FactionCoordinator { get }
    var hud: HUDCoordinator { get }
    var inventory: InventoryCoordinator { get }
    var magic: MagicCoordinator { get }
    var magicWorld: MagicWorldAdapter { get }
    var mapWorld: MapWorldAdapter { get }
    var menuWorld: MenuWorldAdapter { get }
    var packages: PackageCoordinator { get }
    var perception: PerceptionCoordinator { get }
    var perks: PerkCoordinator { get }
    var player: PlayerCoordinator { get }
    var playerSettingsStore: PlayerSettingsStore { get }
    var progression: ProgressionCoordinator { get }
    var ragdoll: RagdollCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var scripts: ScriptCoordinator { get }
    var sessionWiring: WorldSessionWiring { get }
    var storyWorld: StoryWorldAdapter { get }
    var streamer: CellStreamer? { get }
    var worldData: WorldDataStores? { get }
    var worldState: WorldStateStore { get }
}

/// Answers `CombatWorld` from the session systems `game` owns.
final class CombatWorldAdapter {
    unowned let game: any CombatWorldHost
    /// Rigs whose reaction clips were requested, because a room of actors shares one rig.
    private var warmedSkeletons: Set<String> = []

    init(game: any CombatWorldHost) {
        self.game = game
    }

    /// Nil without game data: the runtimes stay nil, and no fight starts with
    /// invented numbers.
    func sessionData() -> CombatSessionData? {
        guard let provider = game.worldData else { return nil }
        let settings = provider.gameSettings
        let text: GameTextResolver = { [game] in game.mapWorld.text($0) }
        var data = CombatSessionData(
            combat: provider.combatSettings,
            archery: provider.archerySettings,
            items: Self.items(provider),
            impacts: Self.impacts(provider)
        )
        data.difficulty = provider.difficultySettings
        data.weaponDamage = WeaponDamageSettings.resolve(store: settings, text: text)
        data.stamina = StaminaSettings.resolve(store: settings)
        data.powerAttacks = PowerAttackSettings.resolve(store: settings)
        data.skillUses = MeleeSkillUseSettings.resolve(store: settings)
        data.staggers = StaggerSettings.resolve(store: settings)
        data.combatAI = CombatAISettings.resolve(store: settings)
        data.arrows = ArrowSettings.resolve(store: settings, text: text)
        data.falls = FallDamageSettings.resolve(store: settings)
        return data
    }

    func wireMelee(gameSession: GameSession) {
        let combat = game.combat
        // A frame step, not the audio tick: a swing must resolve with audio off.
        let frameSteps = gameSession.frameSteps
        frameSteps.register(.melee) { [weak self, weak combat, weak gameSession] _ in
            guard let combat, let gameSession else { return }
            let locomotion = gameSession.locomotion
            if gameSession.movementMode.isPlayerControlled, let self {
                combat.notePlayerSneaking(game.player.isSneaking)
            }
            if let landing = gameSession.walkController.takeLanding() {
                combat.applyFall(height: landing.height, speed: landing.speed, to: .player)
            }
            for (name, value) in combat.perkGraphFlagChanges() {
                locomotion.write(.bool(value), to: name)
            }
            let commands = combat.advanceMelee(
                events: locomotion.graphEvents.drain(locomotion.meleeEventConsumer),
                intent: locomotion.meleeIntent,
                isPlayerControlled: gameSession.movementMode.isPlayerControlled
            )
            self?.run(commands)
        }
    }

    func wireArchery(gameSession: GameSession) {
        let combat = game.combat
        // The world tick delivers a zero delta on a menu-paused frame, so an
        // arrow hangs in the air behind an open menu.
        let worldTick = gameSession.worldTick
        worldTick.register(.archery) { [weak self, weak combat, weak gameSession] delta in
            guard let combat, let gameSession else { return }
            let locomotion = gameSession.locomotion
            combat.isTimeSlowed = gameSession.magicTimeScale < 1
            let commands = combat.advanceArchery(
                events: locomotion.graphEvents.drain(locomotion.archeryEventConsumer),
                intent: locomotion.archeryIntent,
                isPlayerControlled: gameSession.movementMode.isPlayerControlled,
                delta: delta
            )
            gameSession.bowZoomTimeScale = combat.bowZoomTimeScale
            gameSession.bowZoomViewShare = combat.archery?.zoom.viewShare ?? 1
            self?.run(commands)
        }
    }

    /// Wired after melee, archery and the ragdolls, so the loop steps last.
    func wireLoop(gameSession: GameSession) {
        let combat = game.combat
        let store = game.playerSettingsStore
        combat.load(settings: store)
        // The launcher page writes the switch while a session runs.
        store.observe { [weak combat, weak store] id in
            guard id == .combatTemperament || id == .combatGameSettings, let store else { return }
            combat?.load(settings: store)
        }
        gameSession.worldTick.register(.combatLoop) { [weak combat, weak self] delta in
            self?.run(combat?.advanceLoop(by: delta) ?? [])
            self?.updateNPCDrawStates()
        }
    }

    /// Runs what a combat step asked of the session.
    func run(_ commands: [CombatCommand]) {
        for command in commands {
            switch command {
            case let .showNotification(text): game.hud.showNotification(text)
            case let .playImpact(impact, position): playImpact(impact, at: position)
            case let .detectionEvent(owner, position):
                game.perception.runtime?.noteDetectionEvent(owner: owner, at: position)
            case let .removeReference(key): game.worldState.reset(key)
            case .resetRagdolls: game.ragdoll.runtime?.reset()
            case let .setCombatMusic(active): game.audio.musicDirector?.setCombatActive(active)
            case let .playerAttackedOutsideCombat(use):
                game.storyWorld.commentOnPlayer(.playerAction(use == .swing ? "SWMW" : "FIWE"))
            case let .drewBlood(hit, target): drewBlood(hit, target: target)
            case let .playerBowShot(weapon, ammunition, power):
                game.scripts.runtime?.queuePlayerBowShot(
                    weapon: weapon, ammunition: ammunition, power: power,
                    sunGazing: game.scripts.bridge?.isPlayerSunGazing ?? false
                )
            case let .showDefaultBlood(target, position, melee):
                showDefaultBlood(on: target, at: position, melee: melee)
            }
        }
    }

    /// Only the player has a graph with a draw state, so an NPC draws while it fights.
    private func updateNPCDrawStates() {
        guard let loop = game.combat.loop else { return }
        for actor in game.actorWorld.combatActors() {
            game.actorPlayback(for: actor.key)?.weaponsDrawn = loop
                .activity(of: actor.key) == .fighting
        }
    }

    private static func items(_ provider: WorldDataStores) -> ItemDefinitionStore? {
        provider.inventoryBaselines?.items
    }

    private static func impacts(_ provider: WorldDataStores) -> MeleeImpactResolver? {
        provider.footstepStore.map { MeleeImpactResolver(footsteps: $0) }
    }

    /// Plays one reaction clip on a resident actor. False when the actor has
    /// no playback or its rig has no such animation.
    func playReaction(_ clip: CombatActorClip, on key: ReferenceKey) -> Bool {
        guard
            let renderer = game.renderer,
            let playback = game.actorPlayback(for: key),
            let loaded = reactionClip(clip, skeletonMeshPath: playback.clip.skeletonMeshPath)
        else { return false }
        playback.play(
            loaded,
            startingAt: renderer.animationTime,
            forSeconds: ActorAnimationClipLoader.holdSeconds(for: clip)
        )
        return true
    }

    /// The clip when it is loaded. The first ask for a skeleton warms every reaction
    /// of that rig off the main actor; a hit before it arrives plays no reaction.
    private func reactionClip(
        _ clip: CombatActorClip,
        skeletonMeshPath: String
    ) -> ActorAnimationClip? {
        guard let clips = game.sessionWiring.animationClips else { return nil }
        if warmedSkeletons.insert(skeletonMeshPath).inserted {
            for other in CombatActorClip.allCases where other != clip {
                clips.prefetch(Self.reactionKey(other, skeletonMeshPath: skeletonMeshPath))
            }
        }
        return clips.value(for: Self.reactionKey(clip, skeletonMeshPath: skeletonMeshPath))
    }

    private static func reactionKey(
        _ clip: CombatActorClip,
        skeletonMeshPath: String
    ) -> ActorClipKey {
        ActorClipKey(
            skeletonMeshPath: skeletonMeshPath,
            animationPath: ActorAnimationClipLoader.animationPath(for: clip)
        )
    }
}
