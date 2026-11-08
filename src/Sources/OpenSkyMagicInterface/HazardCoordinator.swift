import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

/// A placed hazard as a cell build hands it over.
nonisolated public struct HazardPlacement: Equatable, Sendable {
    public let id: ReferenceKey
    public let spec: HazardSpec
    public let position: SIMD3<Float>

    public init(id: ReferenceKey, spec: HazardSpec, position: SIMD3<Float>) {
        self.id = id
        self.spec = spec
        self.position = position
    }
}
