// Live-renderer seam for the `World > First person` section (issue #190).
//
// Same shape as the other panel bridges: one Equatable snapshot crosses from
// the engine to the readout at 2 Hz, plus the settings the section writes.
//
// What the readout has to be able to say, and why each line is here rather
// than inferred: whether the `_1stperson` graph loaded at all and why not if
// it did not, how many arm meshes survived the MOD4/MOD5 projection and how
// many pieces were dropped for declaring none (the flagged assumption in
// `ActorVisualResolutionFirstPerson.swift` — a user who wonders where their
// gauntlets went reads the answer here), whether the rig actually carries the
// `Camera1st [Cam1]` bone the eye rides, and what the arms' own graph is
// firing. None of that is visible from a frame: an arm that is missing and an
// arm that is behind you look the same.

import Foundation
import simd

/// What the first-person readout shows for one refresh.
nonisolated struct FirstPersonSnapshot: Equatable, Sendable {
    let rendererAvailable: Bool
    /// True while the camera is the first-person one, so the arms are drawn.
    let active: Bool
    /// Whether the `_1stperson` behavior graph is attached to the bridge.
    let graphAttached: Bool
    /// Whether an assembled arms rig is attached to the renderer.
    let rigAttached: Bool
    /// Why there are no arms, when there are none.
    let failureReason: String?
    /// Arm meshes the assembly produced, and pieces dropped for declaring no
    /// first-person model.
    let armModelCount: Int
    let droppedPieceCount: Int
    /// Whether the rig declares `Camera1st [Cam1]`, and where that bone is in
    /// rig space right now.
    let hasCameraBone: Bool
    let cameraBoneHeight: Float?
    /// Graph updates the first-person instance has run, and the variable and
    /// event names it declares no home for.
    let graphUpdates: Int
    let missingVariables: [String]
    let missingEvents: [String]
    /// Vertical field of view, degrees.
    let fovYDegrees: Float

    static let unavailable = FirstPersonSnapshot(
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
}

@MainActor
protocol FirstPersonControlProviding: AnyObject {
    var firstPersonSnapshot: FirstPersonSnapshot { get }
    /// Vertical field of view in degrees, clamped by the engine to
    /// `FirstPersonCamera.fovYRange`.
    var firstPersonFOVYDegrees: Float { get set }
    /// Whether the arms are drawn at all. An A/B toggle rather than a game
    /// setting: turning them off is how a capture separates "the arms are
    /// wrong" from "the world behind them is wrong".
    var firstPersonArmsEnabled: Bool { get set }
}
