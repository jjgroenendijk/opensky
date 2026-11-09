// App side of `CinematicCameraCoordinator`: actor anchors, camera tracks from
// the install, the renderer's override pose and time scale, and the kill that
// starts a kill cam. The rules live in the coordinator. See docs/engine/kill-cam.md.

public import Foundation
import OpenSkyActorsInterface
public import OpenSkyCamera
import OpenSkyCells
import OpenSkyCombat
public import OpenSkyCombatInterface
public import OpenSkyConditions
import OpenSkyEffects
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
public import OpenSkyFormatsMesh
public import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
public import OpenSkyWorldInterface
import simd

/// What `CinematicCameraWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol CinematicCameraWorldHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var cinematicCamera: any CinematicCameraPort { get }
    var combat: any CombatPort { get }
    var effects: any EffectsPort { get }
    var factions: any FactionPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var combatRecords: (any CombatRecordsPort)? { get }
}

public final class CinematicCameraWorldAdapter {
    public let game: any CinematicCameraWorldHost
    /// Camera tracks by CAMS model path, all requested at wiring, off the main actor.
    var tracks: AssetLoader<String, NIFCameraTrack>?
    var lastFrame: Date?
    let now: () -> Date

    public init(game: any CinematicCameraWorldHost, now: @escaping () -> Date) {
        self.game = game
        self.now = now
    }

    /// The install's base odds; the rest stay at their defaults.
    public static func killCamSettings(_ data: (any CombatRecordsPort)?) -> KillCamSettings {
        var settings = KillCamSettings()
        if let store = data?.gameSettings {
            settings.baseOdds = KillCamSettings.resolve(store: store).baseOdds
        }
        return settings
    }

    /// A hostile actor died. When it was the last one, a kill cam may play on it.
    public func actorDied(_ key: ReferenceKey) {
        // A kill move started its own kill cam, which keeps playing.
        guard
            key != .player, !game.cinematicCamera.isPlaying,
            game.factions.hostility(of: key) == .hostile
        else { return }
        let remaining = game.actorWorld.combatActors().filter {
            $0.key != key && !$0.isDead && game.factions.hostility(of: $0.key) == .hostile
        }.count
        game.cinematicCamera.playKillCam(
            attacker: .player,
            target: key,
            remainingHostiles: remaining
        )
    }

    public func anchorPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        cinematicAnchor(of: key)?.position
    }
}

extension CinematicCameraWorldAdapter: CinematicCameraWorld {
    public var cameraPaths: CameraPathStore? {
        game.combatRecords?.presentationRecords?.cameras
    }

    public func cameraConditionContext() -> ConditionContext {
        game.runtimeState.conditionContext()
    }

    public func cameraShotFacts(
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

    public func cameraTrack(model: String) -> NIFCameraTrack? {
        tracks?.value(for: model)
    }

    /// The player stands where the capsule is and faces the player's own view,
    /// not the shot's.
    public func cinematicAnchor(of key: ReferenceKey) -> CinematicAnchor? {
        guard let gameSession = game.gameSession else { return nil }
        if key == .player {
            let view = gameSession.dialogueRestorePose ?? gameSession.freeFlyCamera
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
            focusHeight: CinematicAnchor.chestHeight * actor.scale
        )
    }

    public var playerPosition: SIMD3<Float>? {
        game.gameSession?.locomotion.status.feetPosition
    }

    public func apply(_ frame: CinematicFrame) {
        guard let gameSession = game.gameSession else { return }
        gameSession.worldTimeScale = frame.timeScale
        guard
            frame.pose != nil || frame.shake != .zero || gameSession.isCinematicCameraEngaged
            || gameSession.cinematicCameraState.shakeOffset != .zero
        else { return }
        gameSession.setCinematicCamera(frame.pose, shakeOffset: frame.shake)
    }

    public func startImageSpaceModifier(_ key: ReferenceKey) -> Bool {
        guard let gameSession = game.gameSession else { return false }
        return game.effects.startModifier(key, strength: 1, on: &gameSession.imageSpace)
    }
}

extension CinematicCameraWorldAdapter: CinematicCameraWorldPort {}
