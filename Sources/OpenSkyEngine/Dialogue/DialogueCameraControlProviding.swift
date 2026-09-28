// Main-app seam for the dialogue camera and the speaker focus (issue #427,
// roadmap item 17.4, scope point 5).
//
// The same shape as `DialogueControlProviding` beside it: the panel reads one
// snapshot per refresh and calls one mutation entry point per user action, and
// never sees the renderer, the movement runtime or the package runtime.
//
// The force toggle exists because the camera is otherwise reachable only by
// holding a conversation, and a conversation needs an actor with something to
// say standing within the interaction ray's reach. Forcing it on a selected
// actor is what lets the framing, the collision pull-in and the speaker turn be
// checked against any actor in the cell, which is what item 17.8's gate has to
// do.
//
// Documented in docs/engine/dialogue-camera.md.

import OpenSkyFormats
import simd

/// Which actor the force toggle aims at. Two rows rather than a free-text
/// FormID field, for the reason `ActorValueTargetSelector` has two: the
/// question a session asks is "this one in front of me" or "whoever is
/// closest", and a typed FormID is a third thing that can be wrong.
nonisolated public enum DialogueCameraTarget: String, CaseIterable, Equatable, Sendable {
    /// The actor the crosshair is on, which is the one a conversation would
    /// open with.
    case crosshair
    /// The nearest resident actor, so the toggle still has a subject when the
    /// crosshair is on a wall.
    case nearestActor

    public var label: String {
        switch self {
        case .crosshair: "Crosshair target"
        case .nearestActor: "Nearest actor"
        }
    }
}

/// What the speaker focus did to one actor: the turn and the suspended package.
nonisolated public struct DialogueSpeakerFocusRow: Equatable, Sendable {
    /// `NPCMovementState` as the movement authority reports it.
    public let movementState: String
    /// Where the actor is pointing and where it is turning to, in degrees.
    public let yawDegrees: Float
    public let targetYawDegrees: Float
    public let isSettled: Bool
    public let isPackageSuspended: Bool
    /// The package the actor holds while suspended, which is what it goes back
    /// to re-selecting from when the conversation ends.
    public let packageEditorID: String?

    public init(
        movementState: String,
        yawDegrees: Float,
        targetYawDegrees: Float,
        isSettled: Bool,
        isPackageSuspended: Bool,
        packageEditorID: String?
    ) {
        self.movementState = movementState
        self.yawDegrees = yawDegrees
        self.targetYawDegrees = targetYawDegrees
        self.isSettled = isSettled
        self.isPackageSuspended = isPackageSuspended
        self.packageEditorID = packageEditorID
    }
}

/// One sample of everything the dialogue-camera readout shows.
nonisolated public struct DialogueCameraSnapshot: Equatable, Sendable {
    public static let empty = DialogueCameraSnapshot(
        isAvailable: false,
        isEngaged: false,
        isForced: false,
        target: .crosshair,
        speakerName: nil,
        speakerKey: nil,
        pose: nil,
        restoreMode: .fly,
        restoreFOVYDegrees: FirstPersonCamera.defaultFOVYDegrees,
        overlayEnabled: false,
        speakerFocus: nil,
        lastOutcome: nil
    )

    /// False without a live renderer, which is the one case the readout states
    /// rather than reporting a camera that is disengaged.
    public let isAvailable: Bool
    public let isEngaged: Bool
    public let isForced: Bool
    public let target: DialogueCameraTarget
    public let speakerName: String?
    public let speakerKey: ReferenceKey?
    /// The last resolved framing, nil before the first one.
    public let pose: DialogueCameraPose?
    /// The camera mode still live underneath the override, which the view goes
    /// back to looking through when the conversation ends.
    public let restoreMode: CameraMovementMode
    /// The field of view that mode projects with, which the projection is
    /// rebuilt to on release.
    public let restoreFOVYDegrees: Float
    public let overlayEnabled: Bool
    public let speakerFocus: DialogueSpeakerFocusRow?
    public let lastOutcome: String?

    public init(
        isAvailable: Bool,
        isEngaged: Bool,
        isForced: Bool,
        target: DialogueCameraTarget,
        speakerName: String?,
        speakerKey: ReferenceKey?,
        pose: DialogueCameraPose?,
        restoreMode: CameraMovementMode,
        restoreFOVYDegrees: Float,
        overlayEnabled: Bool,
        speakerFocus: DialogueSpeakerFocusRow?,
        lastOutcome: String?
    ) {
        self.isAvailable = isAvailable
        self.isEngaged = isEngaged
        self.isForced = isForced
        self.target = target
        self.speakerName = speakerName
        self.speakerKey = speakerKey
        self.pose = pose
        self.restoreMode = restoreMode
        self.restoreFOVYDegrees = restoreFOVYDegrees
        self.overlayEnabled = overlayEnabled
        self.speakerFocus = speakerFocus
        self.lastOutcome = lastOutcome
    }
}

/// Live-renderer seam for the dialogue-camera section.
@MainActor
public protocol DialogueCameraControlProviding: AnyObject {
    var dialogueCameraSnapshot: DialogueCameraSnapshot { get }

    /// Engages the camera on the selected actor without a conversation, or
    /// releases it. A conversation that opens while it is forced takes it over
    /// and closing that conversation hands it back, so the toggle survives a
    /// conversation rather than fighting it.
    var isDialogueCameraForced: Bool { get set }

    /// Which actor the toggle aims at.
    var dialogueCameraTarget: DialogueCameraTarget { get set }

    /// The pivot, sightline and eye gizmo, through the M16 overlay registry.
    var dialogueCameraOverlayEnabled: Bool { get set }
}
