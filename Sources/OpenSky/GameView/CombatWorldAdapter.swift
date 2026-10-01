// App side of `CombatCoordinator`: builds its runtimes from the provider, steps
// them from the renderer's frame hooks, and plays reaction clips. The rules live
// in the coordinator (docs/engine/coordinators.md).

import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsAnimation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyRendering
import OpenSkyWorld

/// Answers `CombatWorld` from the session systems `game` owns.
final class CombatWorldAdapter {
    unowned let game: GameViewController
    /// Reaction clips, decoded once per skeleton and kind, because a room of
    /// actors shares one rig.
    private var clips: [String: ActorAnimationClip] = [:]
    /// Keys whose rig has no such clip, so they are not decoded again.
    private var unresolvableClips: Set<String> = []

    init(game: GameViewController) {
        self.game = game
    }

    /// Without combat settings, which is every synthetic scene, the runtime
    /// stays nil and no fight starts with invented numbers.
    func wireMelee(provider: any WorldDataProviding, renderer: Renderer) {
        guard let settings = (provider as? CombatDataProviding)?.combatSettings else { return }
        let combat = game.combat
        combat.attach(world: self)
        combat.wireMelee(
            settings: settings,
            items: Self.items(provider),
            impacts: Self.impacts(provider)
        )
        // `onFrame`, not the audio tick: a swing must resolve with audio off.
        renderer.onFrame.add { [weak combat, weak renderer] _ in
            guard let combat, let renderer else { return }
            let locomotion = renderer.locomotion
            combat.advanceMelee(
                events: locomotion.graphEvents.drain(locomotion.meleeEventConsumer),
                intent: locomotion.meleeIntent,
                isPlayerControlled: renderer.movementMode.isPlayerControlled
            )
        }
    }

    func wireArchery(provider: any WorldDataProviding, renderer: Renderer) {
        guard let settings = (provider as? CombatDataProviding)?.archerySettings else { return }
        let combat = game.combat
        combat.attach(world: self)
        combat.wireArchery(
            settings: settings,
            items: Self.items(provider),
            impacts: Self.impacts(provider)
        )
        // `onWorldUpdate` delivers a zero delta on a menu-paused frame, so an
        // arrow hangs in the air behind an open menu.
        let advanceOthers = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak combat, weak renderer] delta in
            advanceOthers?(delta)
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
    func wireLoop(provider: any WorldDataProviding, renderer: Renderer) {
        guard let settings = (provider as? CombatDataProviding)?.combatSettings else { return }
        let combat = game.combat
        combat.attach(world: self)
        combat.wireLoop(settings: settings)
        let advanceWorld = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak combat] delta in
            advanceWorld?(delta)
            combat?.advanceLoop(by: delta)
        }
    }

    private static func items(_ provider: any WorldDataProviding) -> ItemDefinitionStore? {
        (provider as? ItemDataProviding)?.inventoryBaselines?.items
    }

    private static func impacts(_ provider: any WorldDataProviding) -> MeleeImpactResolver? {
        (provider as? AudioDataProviding)?.footstepStore.map { MeleeImpactResolver(footsteps: $0) }
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

    private func reactionClip(
        _ clip: CombatActorClip,
        skeletonMeshPath: String
    ) -> ActorAnimationClip? {
        let cacheKey = "\(skeletonMeshPath)#\(clip.rawValue)"
        guard !unresolvableClips.contains(cacheKey) else { return nil }
        if let cached = clips[cacheKey] {
            return cached
        }
        guard
            let fileSystem = game.audioFileSystem,
            let loaded = try? ActorAnimationClipLoader.clip(
                skeletonMeshPath: skeletonMeshPath,
                animationPath: ActorAnimationClipLoader.animationPath(for: clip),
                readHKX: { path in try HKXFile(data: fileSystem.contents(forPath: path)) }
            )
        else {
            unresolvableClips.insert(cacheKey)
            return nil
        }
        clips[cacheKey] = loaded
        return loaded
    }
}
