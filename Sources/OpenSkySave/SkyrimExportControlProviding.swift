// The Skyrim export state. The app answers it from the
// running session. See docs/engine/ess-export.md.

import Foundation

nonisolated public enum SkyrimExportOutcome: Equatable, Sendable {
    case none
    case running
    /// The file name written and the report lines.
    case exported(String, [String])
    case failed(String)
}
