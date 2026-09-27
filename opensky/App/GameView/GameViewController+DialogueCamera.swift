// Live app wiring for the dialogue camera and the speaker focus (issue #427,
// roadmap item 17.4).
//
// Two things happen here and they are deliberately one file, because they are
// one behaviour: while somebody is being talked to, the view frames them and
// they stand still facing the player. Splitting the camera from the focus would
// let a session end up with one without the other.
//
// **The focus is republished every frame rather than latched on entry.** The
// speaker's head moves — it is a bone of a running animation — and the player
// can walk around a speaker mid-conversation, so a framing computed once at
// entry would be stale by the second sentence. Recomputing it is a bone lookup
// and an `atan2`, which is why it can be done per frame at all.
//
// **What the focus does to the speaker goes through the authorities that
// already own it.** Movement is suspended through `stopActor`, the turn is
// requested through `faceActor`, and the package is held and released through
// `ActorPackageRuntime`. None of it is written directly onto the actor, so
// nothing here can disagree with what the AI does next frame.
//
// See docs/engine/dialogue.md, "Dialogue camera".

import AppKit
import simd

/// Dialogue-camera state the controller owns. Extensions cannot add stored
/// properties, so it lives as one value on `GameViewController`.
struct DialogueCameraBridgeState {
    /// The panel's force toggle: frame the selected actor with no conversation
    /// open at all.
    var isForced = false
    var target: DialogueCameraTarget = .crosshair
    /// The actor the speaker focus is currently holding — turned, movement
    /// stopped, package suspended — or nil when nobody is held.
    var held: ReferenceKey?
    /// Result of the last control, kept across ticker refreshes so the readout
    /// does not erase what the user just did.
    var lastOutcome: String?
}

extension GameViewController {
    /// Publishes the camera's focus once per world update and registers its
    /// gizmo with the M16 overlay registry (issue #422).
    ///
    /// Ordering: this runs after the systems already chained onto
    /// `onWorldUpdate`, so the head bone it samples is the one this frame's
    /// animation pass produced and the actor pose it reads is the one this
    /// frame's movement produced.
    func wireDialogueCamera(renderer: Renderer) {
        let advancePreviousSystems = renderer.onWorldUpdate
        renderer.onWorldUpdate = { [weak self] delta in
            advancePreviousSystems?(delta)
            self?.refreshDialogueCameraFocus()
        }
        renderer.worldOverlaySources
            .register(identifier: "dialogue-camera") { [weak renderer] context, list in
                renderer?.appendDialogueCameraOverlay(context: context, to: &list)
            }
    }

    /// Points the camera at whoever is being talked to, and lets go when
    /// nobody is.
    func refreshDialogueCameraFocus() {
        guard let renderer else { return }
        guard
            let speaker = dialogueCameraSpeaker(),
            let head = dialogueSpeakerHeadPosition(for: speaker)
        else {
            renderer.setDialogueCameraFocus(nil)
            releaseSpeakerFocus()
            return
        }
        renderer.setDialogueCameraFocus(
            DialogueCameraFocus(speaker: speaker, headPosition: head)
        )
        holdSpeakerFocus(on: speaker, playerEye: renderer.playerEyePosition)
    }

    /// Who the camera frames this frame: the open conversation's speaker, else
    /// the forced target, else nobody.
    ///
    /// The conversation outranks the toggle so that forcing the camera and then
    /// talking to somebody else does not leave the view pointed at the wrong
    /// actor mid-sentence.
    func dialogueCameraSpeaker() -> ReferenceKey? {
        if dialogue.isOpen, let speaker = dialogue.model.speakerKey {
            return speaker
        }
        guard dialogueCamera.isForced else { return nil }
        switch dialogueCamera.target {
        case .crosshair:
            return streamer?.talk.speaker
        case .nearestActor:
            guard let renderer, let streamer else { return nil }
            return streamer.nearestActorEntry(to: renderer.playerEyePosition)?.key
        }
    }

    /// Where one actor's head is in the world.
    ///
    /// The posed `NPC Head [Head]` bone where the actor has a running clip,
    /// which is what makes the camera follow a head that a conversation idle is
    /// moving. An actor the animation layer resolved no rig for falls back to
    /// the capsule's own eye height, which is where this engine puts a head
    /// when it has not been told otherwise.
    func dialogueSpeakerHeadPosition(for actor: ReferenceKey) -> SIMD3<Float>? {
        guard
            let streamer,
            let entry = streamer.referenceEntry(key: actor),
            let placed = entry.placedActor
        else { return nil }
        let override = streamer.npcTransform(for: actor)
        let feet = override?.position ?? placed.placement.position
        guard let pose = animatedPose(for: actor), let head = pose[DialogueCamera.headBoneName]
        else {
            return feet + SIMD3<Float>(0, 0, PlayerCapsule.standard.eyeHeight)
        }
        let actorToWorld = MatrixMath.placement(
            position: feet,
            rotation: override?.rotation ?? placed.placement.rotation,
            scale: override?.scale ?? placed.scale
        )
        let world = actorToWorld * head
        return SIMD3(world.columns.3.x, world.columns.3.y, world.columns.3.z)
    }
}

// MARK: - Speaker focus

extension GameViewController {
    /// Stops one actor, turns it towards the player, and holds its package.
    ///
    /// Called every frame while the camera is engaged: the entry work runs once
    /// per speaker, and the re-aim runs always, because a player who walks
    /// around a speaker has to be followed rather than left addressed at the
    /// place they used to be standing.
    private func holdSpeakerFocus(on speaker: ReferenceKey, playerEye: SIMD3<Float>) {
        if let held = dialogueCamera.held, held != speaker {
            releaseSpeakerFocus()
        }
        if dialogueCamera.held == nil {
            dialogueCamera.held = speaker
            packages.runtime?.setSuspended(true, actor: speaker)
            streamer?.stopActor(speaker)
        }
        streamer?.faceActor(speaker, towards: playerEye)
    }

    /// Hands the held actor back: the turn is released where it stands and the
    /// package is re-selected for the world as it is now.
    func releaseSpeakerFocus() {
        guard let speaker = dialogueCamera.held else { return }
        dialogueCamera.held = nil
        streamer?.releaseActorFacing(speaker)
        resumePackage(for: speaker)
    }
}

// MARK: - Panel seam

extension GameViewController: DialogueCameraControlProviding {
    var dialogueCameraSnapshot: DialogueCameraSnapshot {
        guard let renderer else { return .empty }
        let speaker = dialogueCameraSpeaker()
        return DialogueCameraSnapshot(
            isAvailable: true,
            isEngaged: renderer.isDialogueCameraEngaged,
            isForced: dialogueCamera.isForced,
            target: dialogueCamera.target,
            speakerName: speaker.map { dialogueSpeakerLabel(for: $0) },
            speakerKey: speaker,
            pose: renderer.dialogueCameraPose,
            restoreMode: renderer.dialogueCameraRestoreMode,
            restoreFOVYDegrees: MatrixMath.degrees(
                fromRadians: renderer.dialogueCameraRestoreFOVYRadians
            ),
            overlayEnabled: renderer.dialogueCameraOverlayEnabled,
            speakerFocus: dialogueSpeakerFocusRow(),
            lastOutcome: dialogueCamera.lastOutcome
        )
    }

    var isDialogueCameraForced: Bool {
        get { dialogueCamera.isForced }
        set {
            dialogueCamera.isForced = newValue
            refreshDialogueCameraFocus()
            dialogueCamera.lastOutcome = newValue
                ? forcedOutcome()
                : "released the forced camera"
        }
    }

    var dialogueCameraTarget: DialogueCameraTarget {
        get { dialogueCamera.target }
        set {
            dialogueCamera.target = newValue
            refreshDialogueCameraFocus()
            guard dialogueCamera.isForced else { return }
            dialogueCamera.lastOutcome = forcedOutcome()
        }
    }

    var dialogueCameraOverlayEnabled: Bool {
        get { renderer?.dialogueCameraOverlayEnabled ?? false }
        set { renderer?.dialogueCameraOverlayEnabled = newValue }
    }

    /// What the turn and the suspended package currently look like.
    private func dialogueSpeakerFocusRow() -> DialogueSpeakerFocusRow? {
        guard let speaker = dialogueCamera.held, let streamer else { return nil }
        let hold = streamer.npcFacing(for: speaker)
        let readout = streamer.npcMovementReadouts().first { $0.actor == speaker }
        let package = packageReadouts().first { $0.actor == speaker }
        return DialogueSpeakerFocusRow(
            movementState: readout?.state.rawValue ?? "none",
            yawDegrees: MatrixMath.degrees(fromRadians: hold?.yaw ?? readout?.yaw ?? 0),
            targetYawDegrees: MatrixMath.degrees(fromRadians: hold?.targetYaw ?? 0),
            isSettled: hold?.isSettled ?? false,
            isPackageSuspended: package?.isSuspended ?? false,
            packageEditorID: package?.editorID
        )
    }

    /// What forcing the camera just did, worded for the readout.
    private func forcedOutcome() -> String {
        guard let speaker = dialogueCameraSpeaker() else {
            return "no actor to force onto: \(dialogueCamera.target.label.lowercased()) "
                + "picked nobody"
        }
        return "forced onto \(dialogueSpeakerLabel(for: speaker))"
    }
}
