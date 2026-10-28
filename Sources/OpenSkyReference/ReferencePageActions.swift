// The rules behind the launcher's Reference Game buttons, kept out of AppKit so a test
// reaches them: what Export View writes and which save Import Newest Save loads.

import Foundation

nonisolated public struct ReferenceNotice: Equatable, Sendable {
    public var message: String
    public var isProblem: Bool

    public init(_ message: String, isProblem: Bool) {
        self.message = message
        self.isProblem = isProblem
    }
}

nonisolated public enum ReferencePageActions {
    public static let exportHint = "Send View moves the Windows game to OpenSky's view; "
        + "Follow moves OpenSky to the Windows game's."
    public static let startHint = "Start Both puts OpenSky on the left half of the main screen "
        + "and the Windows game on the right."
    public static let startedMessage = "Started the Windows game. Choose Continue there, "
        + "then use the Game menu to export the view and capture both."
    public static let sendingMessage = "Sending OpenSky's view to the Windows game."
    public static let sentMessage = "The Windows game stands at OpenSky's view."
    public static let followedMessage = "OpenSky moves to the Windows game's view."
    public static let noPlayerMessage = "The Windows game has no player in a cell yet."

    public static func loadingMessage(save: String) -> String {
        "Started the Windows game; it loads \(save) from its main menu."
    }

    /// The reference window size when the game starts alone, as `make reference-game` uses.
    public static let defaultWindowSize = (1280, 720)
    /// Seconds a newly started Steam gets to log in before the game starts.
    public static let steamWait = 30

    public static func startingMessage(waitsForSteam: Bool) -> String {
        waitsForSteam
            ? "Starting Windows Steam; the game follows in \(steamWait) seconds."
            : "Starting the Windows game."
    }

    /// `~/Library/Application Support/OpenSky/Reference/<kind>/<UTC time>/`. The app has no
    /// checkout, so its captures and Wine logs go here instead of `.logs/`.
    public static func runFolder(_ kind: String, at date: Date = Date()) throws -> URL {
        let stamp = date.formatted(
            .iso8601.year().month().day().time(includingFractionalSeconds: false)
                .timeSeparator(.omitted).dateSeparator(.omitted)
        )
        let folder = URL.applicationSupportDirectory.appending(
            path: "OpenSky/Reference/\(kind)/\(stamp)", directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes the batch file with the HUD hidden; `view` is nil when no game runs.
    public static func exportView(_ view: ReferenceView?, prefix: URL?) -> ReferenceNotice {
        let ready: ReferencePrefix
        do {
            ready = try ReferenceLauncher.readyPrefix(prefix)
        } catch {
            return ReferenceNotice(error.localizedDescription, isProblem: true)
        }
        guard let view else {
            return ReferenceNotice("Start the game in OpenSky first.", isProblem: true)
        }
        let file = ready.batchFile(named: ReferenceConsoleBatch.defaultName)
        let toggles = ReferenceBatchToggles(hideMenus: true, freezeWorld: false)
        do {
            try ReferenceConsoleBatch.write(view, toggles: toggles, to: [file])
        } catch {
            return ReferenceNotice(
                "Cannot write \(file.lastPathComponent): \(error)",
                isProblem: true
            )
        }
        return ReferenceNotice(
            "Wrote \(file.lastPathComponent). Type 'bat opensky' in the game console.",
            isProblem: false
        )
    }

    /// The newest reference save, or why there is none.
    public static func newestSave(prefix: URL?) -> Result<URL, ReferenceNoticeError> {
        do {
            let ready = try ReferenceLauncher.readyPrefix(prefix)
            guard let save = ReferenceLauncher.newestSave(in: ready) else {
                return .failure(ReferenceNoticeError("The reference game has no save yet."))
            }
            return .success(save)
        } catch {
            return .failure(ReferenceNoticeError(error.localizedDescription))
        }
    }
}

nonisolated public struct ReferenceNoticeError: Error, Equatable, Sendable {
    public var message: String

    public init(_ message: String) {
        self.message = message
    }
}
