// App side of `CombatCoordinator`: builds its runtimes from the provider, steps
// them from the renderer's frame hooks, and plays reaction clips. The rules live
// in the coordinator (docs/engine/coordinators.md).

import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyCrime
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryInterface
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPerception
import OpenSkyProgression
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
    var progression: ProgressionCoordinator { get }
    var ragdoll: RagdollCoordinator { get }
    var renderer: Renderer? { get }
    var scripts: ScriptCoordinator { get }
    var sessionWiring: WorldSessionWiring { get }
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

    /// Without combat settings, which is every synthetic scene, the runtime
    /// stays nil and no fight starts with invented numbers.
    func wireMelee(provider: WorldDataStores, renderer: Renderer) {
        let settings = provider.combatSettings
        let combat = game.combat
        combat.difficultySettings = provider.difficultySettings
        combat.weaponDamage = WeaponDamageSettings
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        combat.stamina = StaminaSettings.resolve(store: provider.gameSettings)
        combat.powerAttacks = PowerAttackSettings.resolve(store: provider.gameSettings)
        combat.wireMelee(
            settings: settings,
            items: Self.items(provider),
            impacts: Self.impacts(provider)
        )
        // A frame step, not the audio tick: a swing must resolve with audio off.
        let frameSteps = renderer.session.frameSteps
        frameSteps.register(.melee) { [weak self, weak combat, weak renderer] _ in
            guard let combat, let renderer else { return }
            let locomotion = renderer.locomotion
            if renderer.movementMode.isPlayerControlled, let self {
                combat.notePlayerSneaking(game.player.isSneaking)
            }
            for (name, value) in combat.perkGraphFlagChanges() {
                locomotion.write(.bool(value), to: name)
            }
            let commands = combat.advanceMelee(
                events: locomotion.graphEvents.drain(locomotion.meleeEventConsumer),
                intent: locomotion.meleeIntent,
                isPlayerControlled: renderer.movementMode.isPlayerControlled
            )
            self?.run(commands)
        }
    }

    func wireArchery(provider: WorldDataStores, renderer: Renderer) {
        let settings = provider.archerySettings
        let combat = game.combat
        combat.arrows = ArrowSettings
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        combat.wireArchery(
            settings: settings,
            items: Self.items(provider),
            impacts: Self.impacts(provider)
        )
        // The world tick delivers a zero delta on a menu-paused frame, so an
        // arrow hangs in the air behind an open menu.
        let worldTick = renderer.session.worldTick
        worldTick.register(.archery) { [weak self, weak combat, weak renderer] delta in
            guard let combat, let renderer else { return }
            let locomotion = renderer.locomotion
            let commands = combat.advanceArchery(
                events: locomotion.graphEvents.drain(locomotion.archeryEventConsumer),
                intent: locomotion.archeryIntent,
                isPlayerControlled: renderer.movementMode.isPlayerControlled,
                delta: delta
            )
            self?.run(commands)
        }
    }

    /// Wired after melee, archery and the ragdolls, so the loop steps last.
    func wireLoop(provider: WorldDataStores, renderer: Renderer) {
        let settings = provider.combatSettings
        let combat = game.combat
        combat.difficultySettings = provider.difficultySettings
        combat.wireLoop(settings: settings)
        renderer.session.worldTick.register(.combatLoop) { [weak combat, weak self] delta in
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
            case let .removeReference(key): game.worldState.reset(key)
            case .resetRagdolls: game.ragdoll.runtime?.reset()
            case let .setCombatMusic(active): game.audio.musicDirector?.setCombatActive(active)
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
