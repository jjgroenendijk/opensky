// Recording double and snapshot builder for the dialogue-camera seam
// (issue #427), shared by the panel suite and by the destination-registry
// satellite.
//
// Its own file for the reason the dialogue fixture beside it has one: stored
// properties cannot live in an extension, so a fake shared across suites has to
// be one type in one file, and `FakeWorldProviders` already sits near the repo
// file-length limit.

import AppKit
@testable import opensky
import simd

/// Builds a `DialogueCameraSnapshot` from only the fields a test cares about.
nonisolated func makeDialogueCameraSnapshot(
    isAvailable: Bool = true,
    isEngaged: Bool = false,
    isForced: Bool = false,
    target: DialogueCameraTarget = .crosshair,
    speakerName: String? = nil,
    speakerKey: ReferenceKey? = nil,
    pose: DialogueCameraPose? = nil,
    restoreMode: CameraMovementMode = .thirdPerson,
    restoreFOVYDegrees: Float = FirstPersonCamera.defaultFOVYDegrees,
    overlayEnabled: Bool = false,
    speakerFocus: DialogueSpeakerFocusRow? = nil,
    lastOutcome: String? = nil
) -> DialogueCameraSnapshot {
    DialogueCameraSnapshot(
        isAvailable: isAvailable,
        isEngaged: isEngaged,
        isForced: isForced,
        target: target,
        speakerName: speakerName,
        speakerKey: speakerKey,
        pose: pose,
        restoreMode: restoreMode,
        restoreFOVYDegrees: restoreFOVYDegrees,
        overlayEnabled: overlayEnabled,
        speakerFocus: speakerFocus,
        lastOutcome: lastOutcome
    )
}

/// One resolved framing, for a readout assertion that wants real numbers.
nonisolated func makeDialogueCameraPose(
    eye: SIMD3<Float> = SIMD3(126, 24, 112),
    target: SIMD3<Float> = SIMD3(0, 0, 112),
    yaw: Float = .pi,
    pitch: Float = 0,
    distance: Float = 128,
    isCollisionLimited: Bool = false
) -> DialogueCameraPose {
    DialogueCameraPose(
        eye: eye,
        target: target,
        yaw: yaw,
        pitch: pitch,
        distance: distance,
        isCollisionLimited: isCollisionLimited
    )
}

/// Records what the dialogue-camera section asked for.
@MainActor
final class FakeDialogueCameraProvider: DialogueCameraControlProviding {
    var snapshot = makeDialogueCameraSnapshot()
    var isDialogueCameraForced = false
    var dialogueCameraTarget = DialogueCameraTarget.crosshair
    var dialogueCameraOverlayEnabled = false

    var dialogueCameraSnapshot: DialogueCameraSnapshot {
        snapshot
    }
}
