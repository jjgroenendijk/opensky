// The dialogue camera and its panel controls. The camera frames the speaker's
// head every frame, because the head moves. The speaker focus that holds the
// speaker still is a `DialogueCoordinator` call. See docs/engine/dialogue-camera.md.

import OpenSkyDialogue
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyMenus
import OpenSkyRendering
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Holds the panel's force toggle and target for `game`.
final class DialogueCameraController {
    unowned let game: GameViewController
    /// Frames the selected actor with no conversation open.
    private(set) var isForced = false
    private(set) var target: DialogueCameraTarget = .crosshair
    /// Kept across readout refreshes, so the user sees what they just did.
    private(set) var lastOutcome: String?

    init(game: GameViewController) {
        self.game = game
    }

    /// Points the camera at whoever is being talked to, and lets go when
    /// nobody is.
    func refreshFocus() {
        guard let renderer = game.renderer else { return }
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
        let package = game.packageReadouts().first { $0.actor == speaker }
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
