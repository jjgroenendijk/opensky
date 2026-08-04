// Renderer bridge for the World > First person section (issue #190). Same
// shape as the other provider extensions: read and write the live renderer on
// the main thread, and degrade to a documented "unavailable" snapshot when
// there is no renderer (Metal 4 missing).

import AppKit
import simd

extension GameViewController: FirstPersonControlProviding {
    var firstPersonSnapshot: FirstPersonSnapshot {
        guard let renderer else { return .unavailable }
        let rig = renderer.playerFirstPersonRig
        let status = renderer.locomotion.status
        return FirstPersonSnapshot(
            rendererAvailable: true,
            active: renderer.areFirstPersonArmsVisible,
            graphAttached: status.firstPersonGraphAvailable,
            rigAttached: rig != nil,
            failureReason: playerBodyBridge.firstPersonFailureReason,
            armModelCount: rig?.assembly.models.count ?? 0,
            droppedPieceCount: Self.droppedPieceCount(of: rig),
            hasCameraBone: rig?.cameraBoneIndex != nil,
            cameraBoneHeight: rig?.cameraBoneMatrix?.columns.3.z,
            graphUpdates: status.firstPersonGraphUpdates,
            missingVariables: status.firstPersonMissingVariables,
            missingEvents: status.firstPersonMissingEvents,
            fovYDegrees: MatrixMath.degrees(
                fromRadians: renderer.firstPersonCamera.fovYRadians
            )
        )
    }

    var firstPersonFOVYDegrees: Float {
        get {
            MatrixMath.degrees(
                fromRadians: renderer?.firstPersonCamera.fovYRadians
                    ?? FirstPersonCamera.defaultFOVYRadians
            )
        }
        set {
            renderer?.setFirstPersonFOVY(radians: MatrixMath.radians(fromDegrees: newValue))
        }
    }

    var firstPersonArmsEnabled: Bool {
        get { renderer?.firstPersonArmsEnabled ?? true }
        set { renderer?.firstPersonArmsEnabled = newValue }
    }

    /// Worn pieces the first-person projection dropped for declaring no
    /// MOD4/MOD5. Counted off the assembly's own reason-tagged skips rather
    /// than recomputed, so the number is the one the renderer actually acted on.
    private static func droppedPieceCount(of rig: PlayerFirstPersonRig?) -> Int {
        guard let rig else { return 0 }
        return rig.assembly.skips.count {
            guard case let .appearance(skip) = $0.subject else { return false }
            return skip.reason == .noFirstPersonModel
        }
    }
}
