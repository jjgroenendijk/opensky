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
        frames.registerAINPCMovement(stage: stage)
        frames.registerAIPackages(stage: stage)
        frames.registerAIPerception(stage: stage)
        frames.registerAIFurniture(stage: stage, worlds: worlds)
        frames.registerAIOverlay(stage: stage)
    }

    /// Loads each skeleton's BBX half extents; nil when the script files are not loaded.
    public func bodyBoundsLoader() -> AssetLoader<String, SIMD3<Float>>? {
        records.bodyBoundsLoader()
    }

    /// The speeds of the movement type the actor's graph is in.
    public func movementSpeeds(of actor: ReferenceKey) -> MovementType.Speeds? {
        records.movementSpeeds(of: actor)
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

extension AIFrameSteps {
    func registerAINPCMovement(stage: SessionStage) {
        AINPCMovementSteps(hosts: hosts).register(stage: stage)
    }

    func registerAIPackages(stage: SessionStage) {
        let gameSession = stage.gameSession
        gameSession.worldTick.register(.packages) { [weak self] delta in
            guard let self, hosts.packages.runtime != nil else { return }
            hosts.packages.advance(by: Float(delta))
            bumps.advanceBumps()
        }
    }

    func registerAIPerception(stage: SessionStage) {
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

    func registerAIFurniture(stage: SessionStage, worlds: AIWorldAdapter.Worlds) {
        let gameSession = stage.gameSession
        gameSession.playerFurniture = worlds
        gameSession.worldTick.register(.furniture) { [weak self] _ in
            self?.seating.poses.releaseMovedPlayer()
            self?.seating.game.furniture.advance()
        }
    }

    func registerAIOverlay(stage: SessionStage) {
        let streamer = stage.streamer
        stage.gameSession.renderer.worldOverlaySources
            .register(identifier: "navigation") { [weak streamer] context, list in
                streamer?.appendNavigationWorldOverlay(context: context, to: &list)
            }
    }
}
