// `AIWorldAdapter` built over the started session: it registers its frame steps and
// session events as it is built (docs/decisions/session-scope.md).

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyNavigation
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

extension AIWorldAdapter {
    /// Without a stage, as in a test, it registers nothing.
    public convenience init(
        game: some AIWorldHosts,
        stage: SessionStage?
    ) {
        self.init(game: game)
        guard let stage else { return }
        registerAINPCMovement(stage: stage)
        registerAIPackages(stage: stage)
        registerAIPerception(stage: stage)
        registerAIFurniture(stage: stage)
        registerAIOverlay(stage: stage)
    }

    /// Loads each skeleton's BBX half extents; nil when the script files are not loaded.
    public func bodyBoundsLoader() -> AssetLoader<String, SIMD3<Float>>? {
        records.bodyBoundsLoader()
    }

    /// The speeds of the movement type the actor's graph is in.
    public func movementSpeeds(of actor: ReferenceKey) -> MovementType.Speeds? {
        records.movementSpeeds(of: actor)
    }

    private func registerAIBodyShapes(stage: SessionStage) {
        let streamer = stage.streamer
        guard let bounds = bodyBoundsLoader() else { return }
        streamer.npcBodyHalfExtents = { [weak game = self.game] actor in
            guard let skeleton = game?.effectsWorld.race(of: actor)?.maleSkeletonPath else {
                return nil
            }
            _ = bounds.drain()
            return bounds.value(for: ActorGraphCore.projectPath(modelPath: skeleton))
        }
    }

    private func registerAIMovementTypes(stage: SessionStage) {
        let streamer = stage.streamer
        streamer.npcMovementSpeeds = { [weak self] actor in self?.movementSpeeds(of: actor) }
    }

    private func registerAINPCMovement(stage: SessionStage) {
        let gameSession = stage.gameSession
        let streamer = stage.streamer
        streamer.npcMovementConfiguration = gameSession.locomotion.configuration.forActors
        let worldState = game.worldState
        streamer.onNPCMovementPersist = { [weak game = self.game] persistence in
            worldState.set(persistence.transform, for: persistence.actor, in: persistence.cell)
            game?.packages.movementSettled(actor: persistence.actor, reason: persistence.reason)
            game?.followerCommands
                .movementSettled(actor: persistence.actor, reason: persistence.reason)
        }
        gameSession.onPlayerWalkArrived = { [weak game = self.game] in
            game?.packages.movementSettled(actor: .player, reason: .arrival)
        }
        streamer.onNPCPosesChanged = { [weak gameSession] deltas in
            gameSession?.instancePoses.npcDeltas = deltas
        }
        streamer.npcStandingActors = { [weak self] in self?.bumps.standingActors() ?? [] }
        registerAIBodyShapes(stage: stage)
        registerAIMovementTypes(stage: stage)
        streamer.npcWaterPushRace = { [weak game = self.game] actor in
            game?.effectsWorld.waterPushRace(of: actor) ?? .normal
        }
        // A walker drawn by the cell it left would vanish when that cell unloads, so
        // it moves into the cell it entered, and the cell it left drops it.
        streamer.onNPCCellHandoff = { [weak game = self.game, weak streamer] persistence in
            guard let cell = persistence.cell, let streamer else { return }
            let drawing = streamer.cellLocation(of: persistence.actor)
            game?.scripts.bridge?.relocate(persistence.actor, to: cell)
            if let drawing, drawing != cell {
                streamer.requestRebuild(of: drawing)
            }
        }
        streamer.onNPCLocomotionDrive = { [weak game = self.game] update in
            game?.actorGraphWorld.drive(update)
            game?.npcAnimation.drive(update)
        }
        streamer.onNPCLanding = { [weak game = self.game] actor, landing in
            game?.combat.applyFall(height: landing.height, speed: landing.speed, to: actor)
        }
    }

    private func registerAIPackages(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.worldTick.register(.packages) { [weak self] delta in
            guard let self, game.packages.runtime != nil else { return }
            game.packages.advance(by: Float(delta))
            bumps.advanceBumps()
        }
    }

    private func registerAIPerception(stage: SessionStage) {
        let gameSession = stage.gameSession
        let renderer = gameSession.renderer
        gameSession.worldTick.register(.perception) { [weak self] delta in
            guard let adapter = self?.perceptionSense else { return }
            adapter.run(adapter.game.perception.advance(by: delta))
            // After the pass, so a trespass is judged against this frame's detection.
            adapter.game.crime.advanceTrespass(by: Double(delta))
            adapter.game.crime.advanceFavour()
            adapter.game.crime.advanceReports()
            adapter.game.crime.advanceJail()
            // After the trespass, so the guards see a bounty charged this frame.
            adapter.game.crimeWorld.run(adapter.game.crime.advanceGuardResponse())
        }
        renderer.worldOverlaySources
            .register(identifier: "detection") { [weak self] context, list in
                self?.perceptionSense.game.perception
                    .appendWorldOverlay(context: context, to: &list)
            }
    }

    private func registerAIFurniture(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.playerFurniture = worlds
        gameSession.worldTick.register(.furniture) { [weak self] _ in
            self?.seating.poses.releaseMovedPlayer()
            self?.seating.game.furniture.advance()
        }
    }

    private func registerAIOverlay(stage: SessionStage) {
        let streamer = stage.streamer
        stage.gameSession.renderer.worldOverlaySources
            .register(identifier: "navigation") { [weak streamer] context, list in
                streamer?.appendNavigationWorldOverlay(context: context, to: &list)
            }
    }
}

/// The package data, body bounds, and movement speeds `AIWorldAdapter` reads from the records.
struct AIRecordReads {
    let game: any AIWorldHost

    func packageData() -> PackageSessionData? {
        guard let provider = game.aiRecords, let store = provider.packageStore else {
            return nil
        }
        let settings = provider.gameSettings
        var data = PackageSessionData(store: store, conditionFunctions: .standard)
        data.guardWarnings = GuardWarningSettings.resolve(store: settings)
        data.sandboxSettings = SandboxSettings.resolve(store: settings)
        data.bumpSettings = BumpReactionSettings.resolve(store: settings)
        data.followSettings = FollowSettings.resolve(store: settings)
        return data
    }

    func bodyBoundsLoader() -> AssetLoader<String, SIMD3<Float>>? {
        guard let fileSystem = game.aiRecords?.scriptFileSystem else { return nil }
        return AssetLoader<String, SIMD3<Float>> { path in
            let file = try NIFFile(data: fileSystem.contents(forPath: path))
            for case let .bound(_, halfExtents) in file.rootExtraData.map(\.value) {
                return halfExtents
            }
            throw AssetLoadFailure(reason: "\(path) has no BBX bound")
        }
    }

    func movementSpeeds(of actor: ReferenceKey) -> MovementType.Speeds? {
        guard let name = game.actorGraphWorld.graphs.movementStateName(of: actor) else {
            return nil
        }
        return game.aiRecords?.movementTypes.type(named: name)?.speeds
    }
}

extension AIWorldAdapter {
    var records: AIRecordReads {
        AIRecordReads(game: game)
    }
}
