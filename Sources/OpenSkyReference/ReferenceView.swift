// What the player sees in OpenSky, in the values the reference game's console takes.
// The app fills it from the session; `ReferenceConsoleBatch` turns it into commands.

import Foundation

nonisolated public struct ReferenceView: Codable, Equatable, Sendable {
    /// The player's feet, in the cell's space for an interior.
    public var feet: [Float]
    /// OpenSky's angles: yaw 0 looks along +X and turns towards +Y; pitch up is positive.
    public var yawDegrees: Float
    public var pitchDegrees: Float
    public var fovYDegrees: Float
    public var gameHour: Float
    public var weatherFormID: UInt32?
    public var worldspaceEditorID: String?
    public var cellGrid: [Int32]?
    public var interiorEditorID: String?
    public var firstPerson: Bool

    public init(
        feet: SIMD3<Float>, yawDegrees: Float, pitchDegrees: Float, fovYDegrees: Float,
        gameHour: Float, place: ReferencePlace, weatherFormID: UInt32?, firstPerson: Bool
    ) {
        self.feet = [feet.x, feet.y, feet.z]
        self.yawDegrees = yawDegrees
        self.pitchDegrees = pitchDegrees
        self.fovYDegrees = fovYDegrees
        self.gameHour = gameHour
        self.weatherFormID = weatherFormID
        self.firstPerson = firstPerson
        switch place {
        case let .exterior(worldspace, grid):
            worldspaceEditorID = worldspace
            cellGrid = [grid.x, grid.y]
        case let .interior(editorID):
            interiorEditorID = editorID
        }
    }

    public var place: ReferencePlace? {
        if let interiorEditorID {
            return .interior(editorID: interiorEditorID)
        }
        guard let worldspaceEditorID, let cellGrid, cellGrid.count == 2 else { return nil }
        return .exterior(worldspace: worldspaceEditorID, grid: SIMD2(cellGrid[0], cellGrid[1]))
    }

    /// Skyrim's `setangle z`: 0 looks north (+Y) and turns clockwise.
    public var skyrimHeadingDegrees: Float {
        let heading = (90 - yawDegrees).truncatingRemainder(dividingBy: 360)
        return heading < 0 ? heading + 360 : heading
    }

    /// Skyrim's `setangle x`: positive looks down.
    public var skyrimPitchDegrees: Float {
        -pitchDegrees
    }

    /// The console's `fov` is a horizontal angle at a 4:3 view (unverified,
    /// docs/tools/reference-game.md#field-of-view).
    public var skyrimFOVDegrees: Float {
        let halfY = fovYDegrees * .pi / 360
        return 2 * atan(tan(halfY) * 4 / 3) * 180 / .pi
    }
}

nonisolated public enum ReferencePlace: Equatable, Sendable {
    case exterior(worldspace: String, grid: SIMD2<Int32>)
    case interior(editorID: String)
}
