// How far a typed change form decoder got. Data is read in flag order, so the first
// part without a documented layout blocks everything after it.

import Foundation

nonisolated public enum ESSDecodeStatus: Equatable, Sendable {
    /// Every byte was read and every set flag has a documented layout.
    case complete
    /// Reading stopped at `blockedBy`; the fields before it are decoded.
    case partial(blockedBy: String)

    public var isComplete: Bool {
        self == .complete
    }

    public var blockedBy: String? {
        switch self {
        case .complete: nil
        case let .partial(blockedBy): blockedBy
        }
    }
}
