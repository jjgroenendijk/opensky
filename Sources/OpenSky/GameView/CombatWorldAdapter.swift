// App side of `CombatCoordinator`: builds its runtimes from the provider, steps
// them from the renderer's frame hooks, and plays reaction clips. The rules live
// in the coordinator (docs/engine/coordinators.md).

import OpenSkyActorsInterface
import OpenSkyBehavior
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyRendering
import OpenSkyWorld

/// Answers `CombatWorld` from the session systems `game` owns.
final class CombatWorldAdapter {
    unowned let game: GameViewController
    /// Rigs whose reaction clips were requested, because a room of actors shares one rig.
    private var warmedSkeletons: Set<String> = []

    init(game: GameViewController) {
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
        combat.attach(world: self)
        combat.wireMelee(
            settings: settings,
            items: Self.items(provider),
            impacts: Self.impacts(provider)
        )
        // A frame step, not the audio tick: a swing must resolve with audio off.
        let frameSteps = renderer.session.frameSteps
        frameSteps.register(.melee) { [weak combat, weak renderer, weak game = self.game] _ in
            guard let combat, let renderer else { return }
            let locomotion = renderer.locomotion
            if renderer.movementMode.isPlayerControlled, let game {
                combat.notePlayerSneaking(game.player.isSneaking)
            }
            for (name, value) in combat.perkGraphFlagChanges() {
                locomotion.write(.bool(value), to: name)
            }
            combat.advanceMelee(
                events: locomotion.graphEvents.drain(locomotion.meleeEventConsumer),
                intent: locomotion.meleeIntent,
                isPlayerControlled: renderer.movementMode.isPlayerControlled
            )
        }
    }

    func wireArchery(provider: WorldDataStores, renderer: Renderer) {
        let settings = provider.archerySettings
        let combat = game.combat
        combat.arrows = ArrowSettings
            .resolve(store: provider.gameSettings) { [game] in game.mapWorld.text($0) }
        combat.attach(world: self)
        combat.wireArchery(
            settings: settings,
            items: Self.items(provider),
            impacts: Self.impacts(provider)
        )
        // The world tick delivers a zero delta on a menu-paused frame, so an
        // arrow hangs in the air behind an open menu.
        renderer.session.worldTick.register(.archery) { [weak combat, weak renderer] delta in
            guard let combat, let renderer else { return }
            let locomotion = renderer.locomotion
            combat.advanceArchery(
                events: locomotion.graphEvents.drain(locomotion.archeryEventConsumer),
                intent: locomotion.archeryIntent,
                isPlayerControlled: renderer.movementMode.isPlayerControlled,
                delta: delta
            )
        }
    }

    /// Wired after melee, archery and the ragdolls, so the loop steps last.
    func wireLoop(provider: WorldDataStores, renderer: Renderer) {
        let settings = provider.combatSettings
        let combat = game.combat
        combat.difficultySettings = provider.difficultySettings
        combat.attach(world: self)
        combat.wireLoop(settings: settings)
        renderer.session.worldTick.register(.combatLoop) { [weak combat, weak self] delta in
            combat?.advanceLoop(by: delta)
            self?.updateNPCDrawStates()
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
