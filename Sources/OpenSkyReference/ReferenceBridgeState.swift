// What the OpenSkyBridge plugin reports from inside the Windows game, as it writes it to
// `state.json` (reference/bridge/, docs/tools/reference-game.md#the-bridge-plugin).

import Foundation

nonisolated public struct ReferenceBridgeState: Codable, Equatable, Sendable {
    public var version: Int
    /// The name of the last command batch the game ran.
    public var batch: String
    public var mainMenu: Bool
    public var loading: Bool
    public var position: [Float]?
    /// The console's angles: positive pitch looks down; heading 0 is north, clockwise.
    public var pitchDegrees: Float?
    public var headingDegrees: Float?
    public var cellFormID: UInt32?
    /// The cell's editor ID; an exterior cell often has none.
    public var cell: String?
    public var interior: Bool?
    public var grid: [Int32]?
    public var worldspace: String?
    public var worldspaceFormID: UInt32?
    public var hour: Float?
    public var weatherFormID: UInt32?
    /// The `fov` console value, the horizontal angle at a 4:3 view.
    public var worldFOV: Float?
    public var firstPersonFOV: Float?
    public var firstPerson: Bool?
    /// The open message box. The game waits until one of its buttons is pressed.
    public var dialog: ReferenceDialog?

    public init(version: Int = 1, batch: String = "", mainMenu: Bool, loading: Bool = false) {
        self.version = version
        self.batch = batch
        self.mainMenu = mainMenu
        self.loading = loading
    }

    /// True once the player stands in a loaded cell, outside the main menu and loading.
    public var inWorld: Bool {
        !mainMenu && !loading && view != nil
    }

    /// The same view in OpenSky's angles, or nil while no player stands in a cell.
    public var view: ReferenceView? {
        guard
            let position, position.count == 3, let pitchDegrees, let headingDegrees,
            let hour, let place
        else { return nil }
        var view = ReferenceView(
            feet: SIMD3(position[0], position[1], position[2]),
            yawDegrees: ReferenceView.yaw(fromHeading: headingDegrees),
            pitchDegrees: -pitchDegrees,
            fovYDegrees: worldFOV.map(ReferenceView.fovY(fromSkyrimFOV:))
                ?? ReferenceView.defaultFOVYDegrees,
            gameHour: hour, place: place, weatherFormID: weatherFormID,
            firstPerson: firstPerson ?? true
        )
        view.interiorFormID = interior == true ? cellFormID : nil
        return view
    }

    private var place: ReferencePlace? {
        if interior == true {
            return cell.map { .interior(editorID: $0) }
        }
        guard let worldspace, let grid, grid.count == 2 else { return nil }
        return .exterior(worldspace: worldspace, grid: SIMD2(grid[0], grid[1]))
    }
}
