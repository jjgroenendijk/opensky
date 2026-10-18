import Foundation
import OpenSkyFormatsESM

/// Why the player has no body. Every case is reported rather than swallowed:
/// a bodiless player in third person looks like a rendering bug, and the panel
/// has to be able to say which of these it actually is.
nonisolated public enum PlayerBodyError: LocalizedError, Equatable {
    case noFileSystem
    case unresolvedBase(FormID, String)
    case noRenderableGeometry([String])
    case behavior(PlayerBehaviorGraphError)

    public var errorDescription: String? {
        switch self {
        case .noFileSystem:
            "no game archives are mounted"
        case let .unresolvedBase(base, reason):
            "player base \(base.description) did not resolve: \(reason)"
        case let .noRenderableGeometry(reasons):
            "player base resolved to no renderable geometry (\(reasons.joined(separator: ", ")))"
        case let .behavior(error):
            error.errorDescription ?? "behavior graph unavailable"
        }
    }
}
