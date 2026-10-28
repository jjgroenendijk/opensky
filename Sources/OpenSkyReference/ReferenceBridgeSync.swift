// The three things the bridge does for the launcher and `openskycli reference`: put the
// Windows game at OpenSky's view, read its view back, and load a save at its main menu.

import Foundation

nonisolated extension ReferenceBridge {
    /// Seconds a cell change or a save load may take, with the loading screen.
    public static let loadTimeout = Duration.seconds(180)

    /// The place command runs first and alone: the rest only holds once the new cell has
    /// loaded, because a cell change puts the player at the cell's own marker.
    public func sendView(
        _ view: ReferenceView, toggles: ReferenceBatchToggles
    ) async throws -> ReferenceBridgeState {
        let lines = try ReferenceConsoleBatch.lines(for: view, toggles: toggles)
        guard let place = view.place, let first = lines.first else {
            throw ReferenceConsoleBatchError.noPlace
        }
        try await run([first])
        _ = try await wait("load the cell", timeout: Self.loadTimeout) {
            $0.inWorld && $0.isAt(place)
        }
        return try await run(Array(lines.dropFirst()))
    }

    /// Waits for the main menu, loads `save` (a file name, with or without `.ess`), then
    /// waits until the player stands in the save's cell.
    public func loadSave(named save: String) async throws -> ReferenceBridgeState {
        _ = try await wait("reach the main menu", timeout: Self.loadTimeout) { $0.mainMenu }
        let name = save.lowercased().hasSuffix(".ess") ? String(save.dropLast(4)) : save
        try await run(["load \(name)"])
        return try await wait("load the save", timeout: Self.loadTimeout) { $0.inWorld }
    }
}

nonisolated extension ReferenceBridgeState {
    /// Whether the player stands in `place`; editor IDs compare without case, as the
    /// console reads them.
    public func isAt(_ place: ReferencePlace) -> Bool {
        switch place {
        case let .interior(editorID):
            interior == true && cell?.lowercased() == editorID.lowercased()
        case let .exterior(worldspace, cellGrid):
            interior == false && self.worldspace?.lowercased() == worldspace.lowercased()
                && grid == [cellGrid.x, cellGrid.y]
        }
    }
}
