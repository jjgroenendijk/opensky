// The dialogue camera and its panel controls. The camera frames the speaker's
// head every frame, because the head moves. The speaker focus that holds the
// speaker still is a `DialogueCoordinator` call. See docs/engine/dialogue-camera.md.

import Foundation
import OpenSkyDialogue
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyMenus
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// What `DialogueCameraController` reads from the session. `GameViewController` conforms.
@MainActor
protocol DialogueCameraHost: AnyObject {
    var dialogue: DialogueCoordinator { get }
    var dialogueMenu: DialogueMenuController { get }
    var dialogueWorld: DialogueWorldAdapter { get }
    var packages: PackageCoordinator { get }
    var raceMenu: RaceMenuCoordinator { get }
    var renderer: Renderer? { get }
    var streamer: CellStreamer? { get }
}

/// Holds the panel's force toggle and target for `game`.
final class DialogueCameraController {
    unowned let game: any DialogueCameraHost
    /// Frames the selected actor with no conversation open.
    private(set) var isForced = false
    private(set) var target: DialogueCameraTarget = .crosshair
    /// Kept across readout refreshes, so the user sees what they just did.
    private(set) var lastOutcome: String?
    /// The player's facing when the race menu opened. Read once, because the
    /// framed pose turns the view and would move the shot every frame.
    private var portraitYaw: Float?
    /// 1 frames the face, 0 the whole body; eased towards the movie's `ZoomPC`.
    private var portraitZoom: Float = 1
    private var lastPortraitTime: Double?

    init(game: any DialogueCameraHost) {
        self.game = game
    }

    /// Points the camera at whoever is being talked to, and lets go when
    /// nobody is.
    func refreshFocus() {
        guard let renderer = game.renderer else { return }
        if game.raceMenu.isOpen {
            let yaw = portraitYaw ?? Self.playerYaw(of: renderer)
            portraitYaw = yaw
            easePortraitZoom(towards: game.raceMenu.isZoomedIn ? 1 : 0)
            renderer.setDialogueCameraFocus(
                Self.portrait(of: renderer, yaw: yaw, zoom: portraitZoom)
            )
            return
        }
        portraitYaw = nil
        portraitZoom = 1
        lastPortraitTime = nil
        guard
            let speaker = speaker(),
            let head = game.dialogueWorld.headPosition(of: speaker)
        else {
            renderer.setDialogueCameraFocus(nil)
            game.dialogue.releaseSpeakerFocus()
            return
        }
        renderer.setDialogueCameraFocus(DialogueCameraFocus(headPosition: head))
        game.dialogue.focus(on: speaker, playerEye: renderer.playerEyePosition)
    }

    /// The race menu shows the player's face from the front, at the player's eye height.
    /// [WARNING] The game's race menu camera is not documented; this reuses the framing.
    /// Zoomed out, the shot aims at the middle of the body from far enough to fit it.
    static func portrait(of renderer: Renderer, yaw: Float, zoom: Float) -> DialogueCameraFocus {
        let eye = renderer.playerEyePosition
        let capsule = renderer.walkController.capsule
        let forward = SIMD3<Float>(cosf(yaw), sinf(yaw), 0)
        let body = eye - SIMD3<Float>(0, 0, capsule.eyeHeight / 2)
        let target = simd_mix(body, eye, SIMD3(repeating: zoom))
        let near = DialogueCamera.framingDistance(capsule: capsule)
        let far = near * capsule.height / DialogueCamera.framedHeight(capsule: capsule)
        let distance = near + (far - near) * (1 - zoom)
        // The resolve stands off `distance` when the viewpoint is that far minus clearance.
        let reach = max(1, distance - DialogueCamera.clearanceBehindPlayer)
        return DialogueCameraFocus(
            headPosition: target, viewpoint: target + forward * reach, framesPlayer: true
        )
    }

    /// About a third of a second from one framing to the other.
    private func easePortraitZoom(towards goal: Float) {
        let now = Date().timeIntervalSinceReferenceDate
        defer { lastPortraitTime = now }
        guard let last = lastPortraitTime else {
            portraitZoom = goal
            return
        }
        let step = Float(min(0.1, max(0, now - last)))
        portraitZoom += (goal - portraitZoom) * min(1, step * 3)
    }

    /// The player's own view yaw, not the framed pose that stands in for it.
    static func playerYaw(of renderer: Renderer) -> Float {
        renderer.dialogueCameraState.restorePose?.yaw ?? renderer.freeFlyCamera.yaw
    }

    /// The conversation outranks the force toggle, so forcing the camera and
    /// then talking to somebody else frames the one who speaks.
    func speaker() -> ReferenceKey? {
        if game.dialogueMenu.isOpen, let speaker = game.dialogueMenu.model.speakerKey {
            return speaker
        }
        guard isForced else { return nil }
        switch target {
        case .crosshair:
            return game.streamer?.talk.speaker
        case .nearestActor:
            guard let renderer = game.renderer, let streamer = game.streamer else { return nil }
            return streamer.nearestActorEntry(to: renderer.playerEyePosition)?.key
        }
    }

    func setForced(_ forced: Bool) {
        isForced = forced
        refreshFocus()
        lastOutcome = forced ? forcedOutcome() : "released the forced camera"
    }

    func setTarget(_ newTarget: DialogueCameraTarget) {
        target = newTarget
        refreshFocus()
        guard isForced else { return }
        lastOutcome = forcedOutcome()
    }

    private func forcedOutcome() -> String {
        guard let speaker = speaker() else {
            return "no actor to force onto: \(target.label.lowercased()) picked nobody"
        }
        return "forced onto \(game.dialogueWorld.speakerLabel(for: speaker))"
    }

    // MARK: - Snapshot

    var snapshot: DialogueCameraSnapshot {
        guard let renderer = game.renderer else { return .empty }
        let speaker = speaker()
        return DialogueCameraSnapshot(
            isAvailable: true,
            isEngaged: renderer.isDialogueCameraEngaged,
            isForced: isForced,
            target: target,
            speakerName: speaker.map { game.dialogueWorld.speakerLabel(for: $0) },
            speakerKey: speaker,
            pose: renderer.dialogueCameraPose,
            restoreMode: renderer.dialogueCameraRestoreMode,
            restoreFOVYDegrees: MatrixMath.degrees(
                fromRadians: renderer.dialogueCameraRestoreFOVYRadians
            ),
            speakerFocus: speakerFocusRow(),
            lastOutcome: lastOutcome
        )
    }

    private func speakerFocusRow() -> DialogueSpeakerFocusRow? {
        guard let speaker = game.dialogue.heldSpeaker, let streamer = game.streamer else {
            return nil
        }
        let hold = streamer.npcFacing(for: speaker)
        let readout = streamer.npcMovementReadouts().first { $0.actor == speaker }
        let package = game.packages.readout(for: speaker)
        return DialogueSpeakerFocusRow(
            movementState: readout?.state.rawValue ?? "none",
            yawDegrees: MatrixMath.degrees(fromRadians: hold?.yaw ?? readout?.yaw ?? 0),
            targetYawDegrees: MatrixMath.degrees(fromRadians: hold?.targetYaw ?? 0),
            isSettled: hold?.isSettled ?? false,
            isPackageSuspended: package?.isSuspended ?? false,
            packageEditorID: package?.editorID
        )
    }
}
