// The coordinators and adapters the session scope builds in more than one line: the
// menus, the object animation coordinators that share the "Animated objects" switch,
// and the parts that get session state as closures.

import AppKit
import MetalKit
import OpenSkyActorAdapters
import OpenSkyActorPresentation
import OpenSkyActors
import OpenSkyAgentAdapters
import OpenSkyAIAdapters
import OpenSkyAIPackages
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyCrime
import OpenSkyDialogue
import OpenSkyDialogueInterface
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryAdapters
import OpenSkyLoading
import OpenSkyMagic
import OpenSkyMagicAdapters
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyObjectAnimation
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionAdapters
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptAdapters
import OpenSkyScripting
import OpenSkySessionAdapters
import OpenSkySessionInterface
import OpenSkyStoryAdapters
import OpenSkyWorld
import OpenSkyWorldState

/// Builds parts of `GameSessionScope`, so the scope keeps only its wiring list.
struct GameSessionScopeFactories {
    unowned let scope: GameSessionScope
}

extension GameSessionScopeFactories {
    func makeSystemMenu() -> SystemMenuCoordinator {
        let menu = SystemMenuCoordinator(
            menuMode: scope.menuMode,
            movies: scope.swfMovies,
            hud: scope.hud,
            settings: scope.playerSettings,
            saves: scope.saveGames,
            world: scope.ports
        )
        menu.topicSource = scope.messageWorld
        return menu
    }

    func makeRaceMenu() -> RaceMenuCoordinator {
        RaceMenuCoordinator(
            menuMode: scope.menuMode,
            movies: scope.swfMovies,
            hud: scope.hud,
            world: scope.menuWorld,
            morphCounts: scope.worldData
                .map { FaceMorphCounts.resolve(store: $0.gameSettings) } ?? .vanilla
        )
    }

    func makeMenuScreenCoordinators() -> MenuScreenCoordinators {
        let (mode, movies, hud, world) = (
            scope.menuMode, scope.swfMovies, scope.hud, scope.menuScreensWorld
        )
        return MenuScreenCoordinators(
            sleepWait: SleepWaitMenuCoordinator(
                menuMode: mode,
                movies: movies,
                hud: hud,
                world: world
            ),
            training: TrainingMenuCoordinator(
                menuMode: mode,
                movies: movies,
                hud: hud,
                world: world
            ),
            book: BookMenuCoordinator(menuMode: mode, movies: movies, hud: hud, world: world),
            tutorial: TutorialMenuCoordinator(
                menuMode: mode,
                movies: movies,
                hud: hud,
                world: world
            ),
            magic: MagicMenuCoordinator(menuMode: mode, movies: movies, hud: hud, world: world),
            gift: GiftMenuCoordinator(menuMode: mode, movies: movies, hud: hud, world: world),
            crafting: CraftingMenuCoordinator(
                menuMode: mode,
                movies: movies,
                hud: hud,
                world: world
            ),
            textEntry: TextEntryMenuCoordinator(
                menuMode: mode,
                movies: movies,
                hud: hud,
                world: world
            ),
            creationClub: CreationClubMenuCoordinator(
                menuMode: mode, movies: movies, hud: hud, world: world
            ),
            mapMovie: MapMenuMovieScreen(map: scope.mapMenu, movies: movies, hud: hud, world: world)
        )
    }

    func makeSequenceDoors() -> SequenceDoorCoordinator {
        let doors = SequenceDoorCoordinator(
            world: scope.objectAnimationWorld, viewer: { [unowned scope] in scope.billboardViewer }
        )
        doors.isEnabled = scope.objectBehaviors.isEnabled
        return doors
    }

    func makeNodeControllers() -> NodeControllerCoordinator {
        let nodes = NodeControllerCoordinator(world: scope.objectAnimationWorld)
        nodes.isEnabled = scope.objectBehaviors.isEnabled
        return nodes
    }

    func makeMenuWorld() -> MenuWorldAdapter {
        let adapter = MenuWorldAdapter(game: scope.ports)
        adapter.state.terminateApp = { NSApplication.shared.terminate(nil) }
        adapter.state.applyViewBindings = { [unowned scope] in
            (scope.hostView as? GameMetalView)?.bindings = $0
        }
        return adapter
    }

    func makeAgentWorld() -> AgentWorldAdapter {
        let adapter = AgentWorldAdapter(game: scope.ports)
        adapter.terminateApp = { NSApplication.shared.terminate(nil) }
        return adapter
    }

    func makeBenchmarkWorld() -> BenchmarkWorldAdapter {
        let adapter = BenchmarkWorldAdapter(game: scope.ports)
        adapter.view = BenchmarkViewSurface(view: scope.hostView)
        return adapter
    }

    func makeScriptWorld() -> ScriptWorldAdapter {
        let adapter = ScriptWorldAdapter(game: scope.ports)
        adapter.state.weather = { [unowned scope] in scope.gameSession?.weather }
        return adapter
    }

    func makePlayerWorld() -> PlayerWorldAdapter {
        let adapter = PlayerWorldAdapter(game: scope.ports)
        adapter.state.locomotion = { [unowned scope] in scope.gameSession?.locomotion }
        adapter.state
            .firstPersonRig = { [unowned scope] in scope.gameSession?.playerFirstPersonRig }
        adapter.state.playerFace = { [unowned scope] in scope.gameSession?.playerBody?.face }
        return adapter
    }

    func makeNPCAnimation() -> NPCAnimationCoordinator {
        let coordinator = NPCAnimationCoordinator(world: scope.aiWorld)
        coordinator.actorPlayback = { [unowned scope] in scope.actorPlayback(for: $0) }
        return coordinator
    }

    func makeIdles() -> IdleCoordinator {
        let idleWorld = scope.idleWorld
        let coordinator = IdleCoordinator(world: idleWorld, data: idleWorld.sessionData())
        coordinator.actorPlayback = { [unowned scope] in scope.actorPlayback(for: $0) }
        return coordinator
    }

    func makeObjectAnimationWorld() -> ObjectAnimationWorldAdapter {
        let adapter = ObjectAnimationWorldAdapter(game: scope.ports)
        adapter.animatedObjects = { [unowned scope] in
            scope.streamer.residentAnimatedObjects()
        }
        adapter.sequenceDoors = { [unowned scope] in scope.streamer.residentSequenceDoors() }
        adapter.nodeAnimations = { [unowned scope] in
            scope.streamer.residentNodeAnimations()
        }
        return adapter
    }

    func makeEffectModelPoser() -> EffectModelPoser {
        let poser = EffectModelPoser(
            files: { [unowned scope] in scope.audioFileSystem },
            meshes: { [unowned scope] in scope.effects.meshes },
            graphs: scope.effectGraphs,
            viewer: { [unowned scope] in scope.billboardViewer }
        )
        poser.isEnabled = scope.objectBehaviors.isEnabled
        return poser
    }

    func makeActorGraphs() -> ActorGraphCoordinator {
        let coordinator = ActorGraphCoordinator(
            world: scope.actorGraphWorld, files: { [unowned scope] in scope.audioFileSystem }
        )
        coordinator.actorPlayback = { [unowned scope] in scope.actorPlayback(for: $0) }
        return coordinator
    }

    func makeScenes() -> SceneCoordinator {
        SceneCoordinator(
            dialogue: scope.dialogue,
            world: scope.storyWorld,
            catalog: scope.worldData.flatMap { data in
                data.storyData.scenes.flatMap { store in
                    data.questStore.map { SceneCatalog(store: store, resolver: $0.resolver) }
                }
            } ?? .empty,
            repeatPause: scope.dialogue.speechTimers.sceneRepeatPause
        )
    }

    func makeStoryManager() -> StoryManagerCoordinator {
        StoryManagerCoordinator(
            world: scope.storyWorld,
            social: SocialEventCoordinator(
                world: scope.storyWorld,
                settings: scope.worldData?.storyData.social ?? .documentedDefaults
            ),
            story: scope.worldData?.storyData.storyManager
        )
    }

    func makeHazardWorld() -> HazardWorldAdapter {
        HazardWorldAdapter(HazardWorldDependencies(
            hazards: { [unowned scope] in scope.hazards },
            combat: scope.combat,
            magic: { [unowned scope] in scope.magic },
            spellHits: { [unowned scope] in scope.magicWorld },
            gameSession: { [unowned scope] in scope.gameSession }
        ))
    }

    func makeTrapControl() -> TrapControlAdapter {
        TrapControlAdapter(TrapControlDependencies(streamer: { [unowned scope] in scope.streamer }))
    }

    func makeFactionWorld() -> FactionWorldAdapter {
        FactionWorldAdapter(FactionWorldDependencies(
            factions: { [unowned scope] in scope.factions },
            actors: scope.actorWorld,
            streamer: { [unowned scope] in scope.streamer }
        ))
    }
}
