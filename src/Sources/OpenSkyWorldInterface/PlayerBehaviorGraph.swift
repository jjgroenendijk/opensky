public import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyGameData

nonisolated public enum PlayerBehaviorGraphError: LocalizedError, Equatable, Sendable {
    case missing(String)
    case invalid(String)
    case noGraph(String)
    case noSkeleton(String)

    public var errorDescription: String? {
        switch self {
        case let .missing(path): "behavior asset missing: \(path)"
        case let .invalid(path): "unreadable Havok packfile: \(path)"
        case let .noGraph(path): "no hkbBehaviorGraph in \(path)"
        case let .noSkeleton(path): "no hkaSkeleton in \(path)"
        }
    }
}
