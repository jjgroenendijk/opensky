// The seam the sidebar's Skyrim export control reads. The app answers it from the
// running session. See docs/engine/ess-export.md.

import Foundation

nonisolated public enum SkyrimExportOutcome: Equatable, Sendable {
    case none
    case running
    /// The file name written and the report lines.
    case exported(String, [String])
    case failed(String)

    /// The readout lines: the outcome, then the report.
    public var lines: [String] {
        switch self {
        case .none: ["Export: none"]
        case .running: ["Export: running"]
        case let .exported(name, report): ["Export: \(name)"] + report
        case let .failed(message): ["Export failed: \(message)"]
        }
    }
}

@MainActor
public protocol SkyrimExportControlProviding: AnyObject {
    var lastSkyrimExport: SkyrimExportOutcome { get }
    /// Writes the session as a new `.ess` in the Skyrim saves folder.
    func startSkyrimExport()
}
