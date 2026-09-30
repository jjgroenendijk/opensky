// Recording double and snapshot builder for the dialogue-camera seam, shared by
// the panel suite and the destination-registry suite. Its own file, because a
// shared fake needs stored properties.

import AppKit
@testable import OpenSkyFormatsESM
@testable import OpenSkyMenus
@testable import OpenSkyRendering
import OpenSkyWorldInterface
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
