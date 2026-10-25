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
    public static let exportHint =
        "Export writes 'opensky' into the game folder; type 'bat opensky' in the game console."

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
