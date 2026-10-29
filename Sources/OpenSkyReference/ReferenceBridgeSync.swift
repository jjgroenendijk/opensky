// What the bridge does for the launcher and `openskycli reference`: put the Windows game
// at OpenSky's view, load a save at its main menu, and answer a message box.

import Foundation
import simd

nonisolated extension ReferenceBridge {
    /// Seconds a cell change or a save load may take, with the loading screen.
    public static let loadTimeout = Duration.seconds(180)
    /// A late cell load can still put the player at the cell's marker this long after.
    static let settleTime = Duration.seconds(1)
    static let viewAttempts = 3

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
        // The new cell shows in the state before its load starts; no loading flag shows,
        // because the load stops the plugin too. So the rest runs again if it was undone.
        let rest = Array(lines.dropFirst())
        let feet = SIMD3(view.feet[0], view.feet[1], view.feet[2])
        var result = try await run(rest)
        for _ in 1 ..< Self.viewAttempts {
            try await Task.sleep(for: Self.settleTime)
            let now = try await wait("load the cell", timeout: Self.loadTimeout) { $0.inWorld }
            if now.stands(at: feet) {
                return now
            }
            result = try await run(rest)
        }
        return result
    }

    /// Waits for the main menu, loads `save` (a file name, with or without `.ess`), then
    /// waits until the player stands in the save's cell.
    public func loadSave(named save: String) async throws -> ReferenceBridgeState {
        _ = try await wait("reach the main menu", timeout: Self.loadTimeout) { $0.mainMenu }
        let name = save.lowercased().hasSuffix(".ess") ? String(save.dropLast(4)) : save
        try await run(["load \(name)"])
        return try await wait("load the save", timeout: Self.loadTimeout) { $0.inWorld }
    }

    /// Presses one button of the open message box, such as the Survival Mode question
    /// after a load; `button` is its index or its text.
    public func answer(_ button: String) async throws -> ReferenceBridgeState {
        guard let dialog = state()?.dialog else { throw ReferenceBridgeError.noDialog }
        guard let index = dialog.buttonIndex(of: button) else {
            throw ReferenceBridgeError.noSuchButton(button, dialog.buttons)
        }
        return try await run(["answer \(index)"])
    }
}

nonisolated extension ReferenceBridgeState {
    /// Whether the player's feet are within a step of `feet` on the ground plane.
    public func stands(at feet: SIMD3<Float>) -> Bool {
        guard let position, position.count == 3 else { return false }
        return simd_distance(SIMD2(position[0], position[1]), SIMD2(feet.x, feet.y)) < 32
    }

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
