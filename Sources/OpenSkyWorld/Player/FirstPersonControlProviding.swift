// The `World > First person` seam: one Equatable snapshot at 2 Hz plus the settings it
// writes. It reports whether the `_1stperson` graph loaded, kept and dropped arm meshes,
// the `Camera1st [Cam1]` bone, and the arms' graph events, none of which a frame shows.

import Foundation
import simd

/// What the first-person readout shows for one refresh.
nonisolated public struct FirstPersonSnapshot: Equatable, Sendable {
    public let rendererAvailable: Bool
    /// True while the camera is the first-person one, so the arms are drawn.
    public let active: Bool
    /// Whether the `_1stperson` behavior graph is attached to the bridge.
    public let graphAttached: Bool
    /// Whether an assembled arms rig is attached to the renderer.
    public let rigAttached: Bool
    /// Why there are no arms, when there are none.
    public let failureReason: String?
    /// Arm meshes the assembly produced, and pieces dropped for declaring no
    /// first-person model.
    public let armModelCount: Int
    public let droppedPieceCount: Int
    /// Whether the rig declares `Camera1st [Cam1]`, and where that bone is in
    /// rig space right now.
    public let hasCameraBone: Bool
    public let cameraBoneHeight: Float?
    /// Graph updates the first-person instance has run, and the variable and
    /// event names it declares no home for.
    public let graphUpdates: Int
    public let missingVariables: [String]
    public let missingEvents: [String]
    /// Vertical field of view, degrees.
    public let fovYDegrees: Float

    public static let unavailable = FirstPersonSnapshot(
        rendererAvailable: false,
        active: false,
        graphAttached: false,
        rigAttached: false,
        failureReason: nil,
        armModelCount: 0,
        droppedPieceCount: 0,
        hasCameraBone: false,
        cameraBoneHeight: nil,
        graphUpdates: 0,
        missingVariables: [],
        missingEvents: [],
        fovYDegrees: 0
    )

    public init(
        rendererAvailable: Bool,
        active: Bool,
        graphAttached: Bool,
        rigAttached: Bool,
        failureReason: String?,
        armModelCount: Int,
        droppedPieceCount: Int,
        hasCameraBone: Bool,
        cameraBoneHeight: Float?,
        graphUpdates: Int,
        missingVariables: [String],
        missingEvents: [String],
        fovYDegrees: Float
    ) {
        self.rendererAvailable = rendererAvailable
        self.active = active
        self.graphAttached = graphAttached
        self.rigAttached = rigAttached
        self.failureReason = failureReason
        self.armModelCount = armModelCount
        self.droppedPieceCount = droppedPieceCount
        self.hasCameraBone = hasCameraBone
        self.cameraBoneHeight = cameraBoneHeight
        self.graphUpdates = graphUpdates
        self.missingVariables = missingVariables
        self.missingEvents = missingEvents
        self.fovYDegrees = fovYDegrees
    }
}

@MainActor
public protocol FirstPersonControlProviding: AnyObject {
    var firstPersonSnapshot: FirstPersonSnapshot { get }
    /// Vertical field of view in degrees, clamped by the engine to
    /// `FirstPersonCamera.fovYRange`.
    var firstPersonFOVYDegrees: Float { get set }
    /// Whether the arms are drawn at all. An A/B toggle rather than a game
    /// setting: turning them off is how a capture separates "the arms are
    /// wrong" from "the world behind them is wrong".
    var firstPersonArmsEnabled: Bool { get set }
}
