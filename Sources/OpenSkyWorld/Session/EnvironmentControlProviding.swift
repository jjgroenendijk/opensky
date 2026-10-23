// Narrow live-renderer seams consumed by agent control and the
// frame HUD. No AppKit here on purpose: the file compiles into both the app and
// the CLI target, so a protocol added here needs no project-membership change.

import Foundation
import OpenSkyFormatsCore
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRendering

/// Live camera pose, as one value so a readout and the HUD read the same frame's
/// numbers rather than each polling the parts separately.
nonisolated public struct CameraPoseSnapshot: Equatable, Sendable {
    /// World position in native Skyrim units (docs/decisions/coordinates.md).
    public let position: SIMD3<Float>
    /// Heading in radians about world +Z.
    public let yaw: Float
    /// Elevation in radians, positive looking up.
    public let pitch: Float
    /// Exterior cell the position falls in, by floor division.
    public let cell: CellCoordinate
    public let movementMode: CameraMovementMode

    /// Reported by providers with no live renderer.
    public static let unavailable = CameraPoseSnapshot(
        position: .zero, yaw: 0, pitch: 0, cell: CellCoordinate(x: 0, y: 0), movementMode: .fly
    )

    public var yawDegrees: Float {
        yaw * 180 / .pi
    }

    public var pitchDegrees: Float {
        pitch * 180 / .pi
    }

    public init(
        position: SIMD3<Float>,
        yaw: Float,
        pitch: Float,
        cell: CellCoordinate,
        movementMode: CameraMovementMode
    ) {
        self.position = position
        self.yaw = yaw
        self.pitch = pitch
        self.cell = cell
        self.movementMode = movementMode
    }
}

/// Per-frame scene accounting plus the streaming and memory numbers that answer
/// "is this frame slow because of what is resident?".
nonisolated public struct SceneStatsSnapshot: Equatable, Sendable {
    public let drawCalls: Int
    public let drawnInstances: Int
    public let culledInstances: Int
    public let residentCellCount: Int
    /// Process physical footprint, or nil when the mach call fails.
    public let memoryFootprintMB: Double?

    public init(
        drawCalls: Int,
        drawnInstances: Int,
        culledInstances: Int,
        residentCellCount: Int,
        memoryFootprintMB: Double?
    ) {
        self.drawCalls = drawCalls
        self.drawnInstances = drawnInstances
        self.culledInstances = culledInstances
        self.residentCellCount = residentCellCount
        self.memoryFootprintMB = memoryFootprintMB
    }
}
