// The console batch file that puts the reference game at OpenSky's view. `bat <name>`
// in the game console runs it one line at a time. Command reference:
// https://en.uesp.net/wiki/Skyrim:Console

import Foundation

nonisolated public enum ReferenceConsoleBatchError: Error, Equatable, Sendable {
    case noPlace
}

nonisolated public enum ReferenceConsoleBatch {
    public static let defaultName = "opensky"

    /// One console command per line, CRLF, because the game reads it as a Windows file.
    public static func text(
        for view: ReferenceView, toggles: ReferenceBatchToggles
    ) throws(ReferenceConsoleBatchError) -> String {
        try lines(for: view, toggles: toggles).joined(separator: "\r\n") + "\r\n"
    }

    public static func lines(
        for view: ReferenceView, toggles: ReferenceBatchToggles
    ) throws(ReferenceConsoleBatchError) -> [String] {
        guard let place = view.place, view.feet.count == 3 else { throw .noPlace }
        var lines = switch place {
        case let .exterior(worldspace, grid): ["cow \(worldspace) \(grid.x) \(grid.y)"]
        case let .interior(editorID): ["coc \(editorID)"]
        }
        lines += zip(["x", "y", "z"], view.feet).map { "player.setpos \($0) \(number($1))" }
        lines += [
            "player.setangle x \(number(view.skyrimPitchDegrees))",
            "player.setangle z \(number(view.skyrimHeadingDegrees))",
            "set gamehour to \(number(view.gameHour))"
        ]
        if let weather = view.weatherFormID {
            lines.append("fw " + String(format: "%08X", weather))
        }
        lines.append("fov \(number(view.skyrimFOVDegrees))")
        if toggles.hideMenus {
            lines.append("tm")
        }
        if toggles.freezeWorld {
            lines.append("tfc 1")
        }
        return lines
    }

    /// Writes the same text to each file, such as the prefix's game folder and a run folder.
    public static func write(
        _ view: ReferenceView, toggles: ReferenceBatchToggles, to files: [URL]
    ) throws {
        let text = try text(for: view, toggles: toggles)
        for file in files {
            try Data(text.utf8).write(to: file)
        }
    }

    static func number(_ value: Float) -> String {
        // Adding zero turns -0 into 0, so a level view does not print "-0.00".
        String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), Double(value) + 0)
    }
}

/// Console commands that flip a state, so a second `bat` run turns them off again.
nonisolated public struct ReferenceBatchToggles: Equatable, Sendable {
    /// `tm`: hides the HUD and menus for a clean capture.
    public var hideMenus: Bool
    /// `tfc 1`: freezes the world, so clouds and particles hold still for the capture.
    public var freezeWorld: Bool

    public init(hideMenus: Bool, freezeWorld: Bool) {
        self.hideMenus = hideMenus
        self.freezeWorld = freezeWorld
    }
}
