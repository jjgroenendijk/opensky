import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyWorldInterface
import simd

/// One marker the map knows: where it is and its effective state.
nonisolated public struct MapMarkerSite: Equatable, Sendable {
    public let key: ReferenceKey
    public let name: String
    public let position: SIMD3<Float>
    public var state: MapMarkerState
    /// The `TNAM` marker type, which is also the map movie's icon index.
    public let iconType: UInt8

    public init(
        key: ReferenceKey,
        name: String,
        position: SIMD3<Float>,
        state: MapMarkerState,
        iconType: UInt8 = 0
    ) {
        self.key = key
        self.name = name
        self.position = position
        self.state = state
        self.iconType = iconType
    }
}
