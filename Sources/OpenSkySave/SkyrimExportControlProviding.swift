// The Skyrim export state. The app answers it from the
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
