// The one marker the player places on the world map. See docs/engine/world-map.md.

import Foundation
public import OpenSkyWorldState

/// Keyed by the player. The marker belongs to one map worldspace, so it shows only there.
nonisolated public struct PlayerSetMapMarker: WorldStateComponent, Sendable {
    /// The editor ID of the map worldspace, such as `Tamriel`.
    public var worldspace: String
    public var position: SIMD3<Float>

    public static var componentKind: WorldStateComponentKind {
        .playerSetMapMarker
    }

    public init(worldspace: String, position: SIMD3<Float>) {
        self.worldspace = worldspace
        self.position = position
    }
}

nonisolated extension WorldStateComponentKind {
    public static let playerSetMapMarker = Self(
        rawValue: "playerSetMapMarker", order: 47, affectsCellBuild: false
    )
}
