// The second stage of a session: every adapter and coordinator over the streamer and the
// frame session. Each adapter registers its frame steps and session events as it is
// built, and the phase enums order them (docs/decisions/session-md).

import AppKit
import Foundation
import OpenSkyActorAdapters
import OpenSkyActorPresentation
import OpenSkyAgentAdapters
import OpenSkyAIAdapters
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatAdapters
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventory
import OpenSkyInventoryAdapters
import OpenSkyMagicAdapters
import OpenSkyMenuAdapters
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionAdapters
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionAdapters
import OpenSkySessionInterface
import OpenSkyStoryAdapters
import OpenSkyTerrain
import OpenSkyWeather
import OpenSkyWorld
import OpenSkyWorldInterface
import simd

/// Builds the second stage of a session over its scope.
struct GameSessionScopeBuild {
    unowned let scope: GameSessionScope

    /// The first stage of a session: the streamer over the loaded world. The session scope
    /// is built over it, so every adapter reads a streamer that exists.
    static func makeStreamer(session: CellSession, renderer: Renderer, radius: Int32)
        -> CellStreamer
    {
        CellStreamer(
            center: CellCoordinate(x: FirstRenderCell.gridX, y: FirstRenderCell.gridY),
            radius: radius,
            runner: session.runner,
            sink: { [weak renderer] scene, camera in
                do {
                    try renderer?.setScene(scene, camera: camera)
                } catch {
                    logger.error(
                        "[ERROR] scene swap failed: \(String(describing: error), privacy: .public)"
                    )
                }
            }
        )
    }

    /// Builds every session member over `stage`. A member the frame reads is built here, so
    /// it registers before the first frame.
    func build(over stage: SessionStage) {
        let gameSession = stage.gameSession
        let streamer = stage.streamer
        let provider = stage.data
        scope.streamer.placedRecords = provider.placedRecords
        gameSession.loadedGridRadius = scope.streamer.grid.radius
        scope.streamer.doorState.doors = DoorSettings.resolve(store: provider.gameSettings)
        if let cellRunner = scope.cellRunner {
            gameSession.renderer.attachTextureStreaming(to: cellRunner)
        }
        scope.runtimeState.reloadGlobals()
        scope.streamer.runtimeStates.bind(to: scope.worldState)
        registerAssetDrains(gameSession: gameSession)
        registerFrame(gameSession: gameSession)
        registerWorldQueries(gameSession: gameSession, streamer: streamer)
        registerMenus(gameSession: gameSession)
        GameSessionScopeCellReset.build(
            scope: scope, provider: provider, gameSession: gameSession, streamer: streamer
        )
        gameSession.audio.animationEvents = AnimationEventCoordinator(world: scope.animationEvents)
        buildAdapters()
    }

    /// Each adapter registers as it is built.
    private func buildAdapters() {
        _ = scope.aiWorld
        _ = scope.audioWorld
        _ = scope.scriptWorld
        _ = scope.messageWorld
        _ = scope.inventoryWorld
        _ = scope.lockWorld
        _ = scope.perkActivationWorld
        _ = scope.playerWorld
        _ = scope.actorWorld
        _ = scope.magicWorld
        _ = scope.hazardWorld
        _ = scope.effectsWorld
        _ = scope.trapControl
        _ = scope.combatWorld
        _ = scope.ragdollWorld
        _ = scope.idleWorld
        _ = scope.actorGraphWorld
        _ = scope.vehicleWorld
        _ = scope.mountWorld
        _ = scope.beastForms
        _ = scope.activationRefusals
        _ = scope.dragonFlightWorld
        _ = scope.objectAnimationWorld
        _ = scope.effectGraphWorld
        _ = scope.animationEvents
        _ = scope.dialogueWorld
        _ = scope.storyWorld
        _ = scope.followerCommandWorld
        _ = scope.cinematicWorld
        _ = scope.loadingWorld
        _ = scope.benchmarkWorld
    }

    /// Off-main loads enter before the world tick, and the coordinators that wait on them
    /// go right after.
    private func registerAssetDrains(gameSession: GameSession) {
        let assetDrains = gameSession.assetDrains
        assetDrains.register(.scripts) { [weak scope] _ in scope?.scripts.drainLoads() }
        assetDrains.register(.audio) { [weak scope] _ in scope?.audio.drainLoads() }
        // Menu movies decode off the main actor, so a menu opens without a stall.
        let movies = scope.swfMovies
        movies.prefetch(SWFMovieSource.menuMoviePaths)
        assetDrains.register(.menuMovies) { _ in movies.drain() }
        // One clip loader for idles, gaits, and combat reactions.
        guard let clips = scope.animationClips else { return }
        assetDrains.register(.animationClips) { [weak scope] _ in
            clips.drain()
            scope?.idles.drainLoads()
            scope?.npcAnimation.applyArrivedClips()
        }
    }

    private func registerFrame(gameSession: GameSession) {
        // Published inside the frame's own update, so the poses the pass uploads
        // are the ones this frame simulated.
        scope.streamer.events.onDynamicPosesChanged = { [weak gameSession] deltas in
            gameSession?.instancePoses.dynamicDeltas = deltas
        }
        scope.streamer.events.onLoadDoorUsed = { [weak scope] door in
            scope?.objectAnimationWorld.doors.swingOpen(door.rawValue)
        }
        let input = scope.cameraInput
        gameSession.frameSteps.register(.streaming) { [weak scope, weak gameSession] position in
            guard scope != nil, let gameSession else { return }
            stepStreaming(cameraAt: position, gameSession: gameSession, input: input)
        }
        // The center cell's regions feed region-weighted weather selection, on
        // the draw loop's thread.
        scope.streamer.events.onCenterRegionsChanged = { [weak gameSession] regions in
            gameSession?.weather?.setRegions(regions)
        }
        scope.streamer.events.onInteractionTargetChanged = { [weak scope] target in
            guard let scope else { return }
            scope.hud.updateTarget(scope.inventoryWorld.perks.labelled(target))
            let item = target.flatMap { $0.interaction.action == .take ? $0.interaction.base : nil }
            scope.hud.updateTargetStat(HUDItemStat.of(
                item.flatMap { scope.inventory.itemCards.itemCard(for: $0) },
                texts: scope.mapWorld.settingTexts()
            ))
        }
        gameSession.worldTick.register(.survivalMode) { [weak scope] _ in
            scope?.survivalMode.tick()
        }
        // After streaming, so the HUD reads the streamer's update of this frame.
        gameSession.frameSteps.register(.hud) { [weak scope, weak gameSession] _ in
            guard let scope, let gameSession else { return }
            // Before the HUD draws, so a skill notice from this frame shows now.
            scope.progressionWorld.training.run(scope.progression.takeCommands())
            scope.updateQuestNotices()
            scope.hud.updatePlayerModes(hudModeInputs(gameSession))
            scope.hud.setActivateLocked(scope.playerControlLocks.disabled.contains(.activate))
            if
                let crosshair = scope.followerCommandWorld.crosshair(
                    for: scope.inventoryWorld.perks.labelled(scope.streamer.interactionTarget),
                    texts: scope.mapWorld.settingTexts()
                )
            {
                scope.hud.updateTarget(crosshair.target)
                scope.hud.setIdlePrompt(crosshair.prompt)
            }
            scope.hud.updateFrame()
        }
    }

    /// A rider's use key dismounts, and in command mode it picks the follower's target,
    /// instead of activating the world.
    private func stepStreaming(
        cameraAt position: SIMD3<Float>, gameSession: GameSession, input: CameraInputState
    ) {
        let pressed = input.consumeActivation()
        let takesPress = scope.mountWorld.takeActivation()
            || scope.followerCommandWorld.takeActivation()
        let activate = pressed && !takesPress
        scope.followerCommandWorld.advanceUseKey(
            by: gameSession.lastCameraDelta, isDown: input.isActivationHeld
        )
        scope.streamer.update(
            cameraPosition: position,
            interactionRay: Self.interactionRay(
                of: gameSession, reach: scope.followerCommandWorld.pickReach
            ),
            activate: activate,
            playerCapsule: Self.playerCapsule(of: gameSession),
            frameTime: gameSession.lastCameraDelta
        )
        let walk = gameSession.walkController
        scope.streamer.actors.recordPlayerSwim(at: walk.feetPosition, isSwimming: walk.isSwimming)
    }

    /// The ground, collision, water, and worldspace the session reads from the streamer.
    private func registerWorldQueries(gameSession: GameSession, streamer: CellStreamer) {
        gameSession.motion.terrainSampler = { [weak streamer] position in
            streamer?.collision.sampleTerrain(at: position)
        }
        gameSession.motion.collisionQuery = { [weak streamer] bounds in
            streamer?.collision.characterCollisionCandidates(overlapping: bounds) ?? []
        }
        gameSession.motion.characterCarry = { [weak streamer] capsule, feet in
            streamer?.dynamicBodies.characterCarry(capsule: capsule, feetPosition: feet) ?? .zero
        }
        gameSession.locomotion.sampleWater = { [weak streamer] position in
            streamer?.collision.water(at: position)
        }
        scope.streamer.events.onWorldspaceChanged
            .register(.weather) { [weak gameSession] editorID in
                gameSession?.weather?.setWorldspace(editorID: editorID)
                if let gameSession {
                    Self.holdAtBorders(of: editorID, in: gameSession)
                }
            }
        gameSession.motion.onBorderReached = { [weak scope] in
            guard let scope else { return }
            let texts = scope.mapWorld.settingTexts(WorldRefusalText.self)
            _ = scope.messages.postNotification(texts[.leavingBorderRegion])
        }
    }

    /// Settings, key bindings, menu text, sounds, and the frame tick that every menu movie
    /// shares. Menu mode drives the renderer's world-sim pause and clears held world input
    /// on entry, so no key sticks while the menu owns input.
    private func registerMenus(gameSession: GameSession) {
        let renderer = gameSession.renderer
        scope.playerSettings.loadControlMap(try? scope.controlMapLoader?())
        scope.playerSettings.applyAll()
        scope.audio.engineStarted
            .register(.playerSettings) { [weak scope] _ in scope?.playerSettings.applyAll() }
        if let labels = scope.menuTextLoader?() {
            renderer.swfTextTranslator = { labels.label(for: $0) }
        }
        let router = scope.menuRouter
        router.monitor.onDisconnect = { [weak scope] in
            guard let scope else { return }
            let texts = scope.mapWorld.settingTexts(GamepadNoticeText.self)
            scope.messages.presentChoices(
                title: texts[.title], text: texts[.message], buttons: [texts[.confirm]]
            ) { _ in }
        }
        let sounds = MenuSoundPlayer(MenuSoundDependencies(game: scope.ports))
        renderer.swfSoundPlayer = { sounds.play(editorID: $0 ?? MenuSoundPlayer.okSound) }
        let ticks = router.ticks
        let monitor = router.monitor
        gameSession.frameSteps.register(.menuRouting) { [ticks, weak renderer, monitor] _ in
            ticks.tick(renderer: renderer, monitor: monitor)
        }
        let input = scope.cameraInput
        scope.menuMode.onModeChange = { [weak scope, weak gameSession, weak input] route, paused in
            gameSession?.worldSimPaused = paused
            if let scope {
                (scope.hostView as? GameMetalView)?
                    .setMenuCursorFree(scope.menuRouter.menuCursorFree(for: route))
            }
            // Released on the route flip, not the pause: the dialogue menu
            // captures input without stopping the world.
            if route == .menu {
                input?.releaseAll()
            }
        }
    }

    /// The player states the HUD movie has a mode for.
    private func hudModeInputs(_ gameSession: GameSession) -> HUDModeInputs {
        HUDModeInputs(
            movementDisabled: scope.scripts.bridge?.stateLinks.isPlayerMovementEnabled == false,
            sneaking: scope.player.isSneaking,
            swimming: gameSession.walkController.isSwimming,
            ridingHorse: scope.mounts.drive?.kind == .horse,
            weaponDrawn: scope.combat.isWeaponDrawn
        )
    }

    /// Player-controlled modes only: the fly camera never picks up a target.
    /// Third person aims along the view direction from the orbit position.
    private static func interactionRay(
        of gameSession: GameSession, reach: Float?
    ) -> InteractionRay? {
        guard gameSession.movementMode.isPlayerControlled else { return nil }
        return InteractionRay(
            origin: gameSession.freeFlyCamera.position,
            direction: gameSession.freeFlyCamera.forward,
            maximumDistance: reach ?? InteractionRay.defaultMaximumDistance
        )
    }

    /// The feet position comes from the walk controller, because the streamer
    /// receives only the eye position.
    private static func playerCapsule(of gameSession: GameSession) -> PlayerCapsuleState? {
        guard gameSession.movementMode.isPlayerControlled else { return nil }
        return PlayerCapsuleState(
            capsule: gameSession.walkController.capsule,
            feetPosition: gameSession.walkController.feetPosition
        )
    }

    private static let logger = EngineLogger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "CellStream"
    )
}

extension GameSessionScopeBuild {
    /// The worldspace's border regions hold the player inside them.
    private static func holdAtBorders(of editorID: String, in gameSession: GameSession) {
        guard let store = gameSession.weather?.store else { return }
        let outlines: [[SIMD2<Float>]] = store.worldspaceByEditorID[editorID]
            .map { store.borderOutlines(worldspace: $0) } ?? []
        guard !outlines.isEmpty else {
            gameSession.motion.borderCheck = nil
            return
        }
        gameSession.motion.borderCheck = { @Sendable from, to in
            BorderRegionRule.allows(from: from, to: to, outlines: outlines)
        }
    }
}
