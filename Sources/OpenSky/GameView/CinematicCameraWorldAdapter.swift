// App side of `CinematicCameraCoordinator`: actor anchors, camera tracks from
// the install, the renderer's override pose and time scale, and the kill that
// starts a kill cam. The rules live in the coordinator. See docs/engine/kill-cam.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyWorld
import simd

/// What `CinematicCameraWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol CinematicCameraWorldHost: AnyObject {
    var actorWorld: ActorWorldAdapter { get }
    var cinematicCamera: CinematicCameraCoordinator { get }
    var combat: CombatCoordinator { get }
    var effects: EffectsCoordinator { get }
    var factions: FactionCoordinator { get }
    var renderer: Renderer? { get }
    var gameSession: GameSession? { get }
    var runtimeState: RuntimeStateCoordinator { get }
    var worldData: WorldDataStores? { get }
}

final class CinematicCameraWorldAdapter {
    unowned let game: any CinematicCameraWorldHost
    /// Camera tracks by CAMS model path, all requested at wiring, off the main actor.
    private var tracks: AssetLoader<String, NIFCameraTrack>?
    private var lastFrame: Date?

    init(game: any CinematicCameraWorldHost) {
        self.game = game
    }

    /// The install's base odds; the rest stay at their defaults.
    static func killCamSettings(_ data: WorldDataStores?) -> KillCamSettings {
        var settings = KillCamSettings()
        if let store = data?.gameSettings {
            settings.baseOdds = KillCamSettings.resolve(store: store).baseOdds
        }
        return settings
    }

    func wire(gameSession: GameSession) {
        wireTracks(gameSession: gameSession)
        // Frame steps run under a menu too; the shot keeps real time, so a
        // paused frame advances nothing.
        gameSession.frameSteps.register(.cinematicCamera) { [weak self, weak gameSession] _ in
            guard let self, let gameSession else { return }
            let now = Date()
            let seconds = gameSession.worldSimPaused ? 0 : lastFrame
                .map { now.timeIntervalSince($0) } ?? 0
            lastFrame = now
            apply(game.cinematicCamera.tick(realSeconds: min(seconds, 0.1)))
        }
    }

    /// A hostile actor died. When it was the last one, a kill cam may play on it.
    func actorDied(_ key: ReferenceKey) {
        guard key != .player, game.factions.hostility(of: key) == .hostile else { return }
        let remaining = game.actorWorld.combatActors().filter {
            $0.key != key && !$0.isDead && game.factions.hostility(of: $0.key) == .hostile
        }.count
        game.cinematicCamera.playKillCam(
            attacker: .player,
            target: key,
            remainingHostiles: remaining
        )
    }

    /// A shot whose track has not arrived plays without one, as a shot with no model does.
    private func wireTracks(gameSession: GameSession) {
        guard let files = game.worldData?.scriptFileSystem else {
            return
        }
        let tracks = AssetLoader<String, NIFCameraTrack> { model in
            try NIFCameraTrack(file: NIFFile(data: files.contents(forPath: "meshes\\" + model)))
        }
        for shot in cameraPaths?.shots.records ?? [] {
            if let model = shot.record.model?.path {
                tracks.prefetch(model)
            }
        }
        self.tracks = tracks
        gameSession.assetDrains.register(.cinematicTracks) { _ in tracks.drain() }
    }

    func anchorPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        cinematicAnchor(of: key)?.position
    }
}

extension CinematicCameraWorldAdapter: CinematicCameraWorld {
    var cameraPaths: CameraPathStore? {
        game.worldData?.presentationRecords?.cameras
    }

    func cameraConditionContext() -> ConditionContext {
        game.runtimeState.conditionContext()
    }

    func cameraShotFacts(
        attacker: ReferenceKey,
        target: ReferenceKey?
    ) -> CameraConditionResolution {
        guard
            let gameSession = game.gameSession,
            let anchor = cinematicAnchor(of: attacker) else { return .empty }
        let chest = anchor.focus
        let query = gameSession.collisionQuery ?? { _ in [] }
        var targetBase: FormID?
        if
            let target,
            case let .actor(base)? = game.actorWorld.actorValueHolder(for: target)?.subject
        {
            targetBase = base
        }
        let targetDistance = target.flatMap { cinematicAnchor(of: $0) }
            .map { simd_distance($0.position, anchor.position) }
        var facts = CameraShotFacts.resolution(
            weapon: attacker == .player ? game.combat.playerWeapon() : nil,
            targetBase: targetBase,
            targetDistance: targetDistance,
            yaw: anchor.yaw
        ) { offset in
            DialogueCamera.collisionProbe.resolve(
                pivot: chest,
                offset: offset,
                collisionQuery: query
            ).distance
        }
        facts.playerIsFirstPerson = gameSession.movementMode == .walk
        return facts
    }

    func cameraTrack(model: String) -> NIFCameraTrack? {
        tracks?.value(for: model)
    }

    /// The player stands where the capsule is and faces the player's own view,
    /// not the shot's.
    func cinematicAnchor(of key: ReferenceKey) -> CinematicAnchor? {
        guard let gameSession = game.gameSession else { return nil }
        if key == .player {
            let view = gameSession.dialogueCameraState.restorePose ?? gameSession.freeFlyCamera
            return CinematicAnchor(
                position: gameSession.locomotion.status.feetPosition,
                yaw: view.yaw
            )
        }
        guard let actor = game.actorWorld.combatActor(key: key)
        else { return nil }
        return CinematicAnchor(
            position: actor.feet,
            yaw: actor.facing,
            focusHeight: 96 * actor.scale
        )
    }

    var playerPosition: SIMD3<Float>? {
        game.gameSession?.locomotion.status.feetPosition
    }

    func apply(_ frame: CinematicFrame) {
        guard let gameSession = game.gameSession else { return }
        gameSession.worldTimeScale = frame.timeScale
        guard
            frame.pose != nil || frame.shake != .zero || gameSession.isCinematicCameraEngaged
            || gameSession.cinematicCameraState.shakeOffset != .zero
        else { return }
        gameSession.setCinematicCamera(frame.pose, shakeOffset: frame.shake)
    }

    func startImageSpaceModifier(_ key: ReferenceKey) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        return game.effects.startModifier(key, strength: 1, on: &gameSession.imageSpace)
    }
}
