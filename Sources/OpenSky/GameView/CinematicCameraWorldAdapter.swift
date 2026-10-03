// App side of `CinematicCameraCoordinator`: actor anchors, camera tracks from
// the install, the renderer's override pose and time scale, and the kill that
// starts a kill cam. The rules live in the coordinator. See docs/engine/kill-cam.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyFactions
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld
import simd

final class CinematicCameraWorldAdapter {
    unowned let game: GameViewController
    private var tracks: [String: NIFCameraTrack?] = [:]
    private var lastFrame: Date?

    init(game: GameViewController) {
        self.game = game
    }

    func wire(renderer: Renderer) {
        game.cinematicCamera.attach(world: self)
        // `onFrame` runs under a menu too; the shot keeps real time, so a
        // paused frame advances nothing.
        renderer.onFrame.add { [weak self, weak renderer] _ in
            guard let self, let renderer else { return }
            let now = Date()
            let seconds = renderer.worldSimPaused ? 0 : lastFrame
                .map { now.timeIntervalSince($0) } ?? 0
            lastFrame = now
            game.cinematicCamera.tick(realSeconds: min(seconds, 0.1))
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

    func anchorPosition(of key: ReferenceKey) -> SIMD3<Float>? {
        cinematicAnchor(of: key)?.position
    }
}

extension CinematicCameraWorldAdapter: CinematicCameraWorld {
    var cameraPaths: CameraPathStore? {
        (game.worldData as? PresentationDataProviding)?.presentationRecords?.cameras
    }

    func cameraConditionContext() -> ConditionContext {
        game.runtimeState.conditionContext()
    }

    func cameraShotFacts(
        attacker: ReferenceKey,
        target: ReferenceKey?
    ) -> CameraConditionResolution {
        guard
            let renderer = game.renderer,
            let anchor = cinematicAnchor(of: attacker) else { return .empty }
        let chest = anchor.focus
        let query = renderer.collisionQuery ?? { _ in [] }
        var targetBase: FormID?
        if
            let target,
            case let .actor(base)? = game.actorWorld.actorValueHolder(for: target)?.subject
        {
            targetBase = base
        }
        let targetDistance = target.flatMap { cinematicAnchor(of: $0) }
            .map { simd_distance($0.position, anchor.position) }
        return CameraShotFacts.resolution(
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
    }

    func cameraTrack(model: String) -> NIFCameraTrack? {
        if let cached = tracks[model] {
            return cached
        }
        let fileSystem = (game.worldData as? ScriptDataProviding)?.scriptFileSystem
        let track = try? fileSystem
            .map {
                try NIFCameraTrack(file: NIFFile(data: $0.contents(forPath: "meshes\\" + model)))
            }
        tracks[model] = track
        return track
    }

    /// The player stands where the capsule is and faces the player's own view,
    /// not the shot's.
    func cinematicAnchor(of key: ReferenceKey) -> CinematicAnchor? {
        guard let renderer = game.renderer else { return nil }
        if key == .player {
            let view = renderer.dialogueCameraState.restorePose ?? renderer.freeFlyCamera
            return CinematicAnchor(position: renderer.locomotion.status.feetPosition, yaw: view.yaw)
        }
        guard let actor = game.actorWorld.combatActors().first(where: { $0.key == key })
        else { return nil }
        return CinematicAnchor(
            position: actor.feet,
            yaw: actor.facing,
            focusHeight: 96 * actor.scale
        )
    }

    var playerPosition: SIMD3<Float>? {
        game.renderer?.locomotion.status.feetPosition
    }

    func applyCinematicFrame(pose: CinematicCameraPose?, shake: SIMD3<Float>, timeScale: Float) {
        guard let renderer = game.renderer else { return }
        renderer.worldTimeScale = timeScale
        guard
            pose != nil || shake != .zero || renderer.isCinematicCameraEngaged
            || renderer.cinematicCameraState.shakeOffset != .zero
        else { return }
        renderer.setCinematicCamera(pose, shakeOffset: shake)
    }

    func startImageSpaceModifier(_ key: ReferenceKey) -> Bool {
        guard let renderer = game.renderer else { return false }
        return game.effects.startModifier(key, strength: 1, on: &renderer.imageSpace)
    }
}
