import Foundation
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyShaderTypes
import OpenSkyWorldState
import simd

/// Teleport-capable DOOR placement retained beside render data so main-thread
/// interaction can select a nearby door without touching plugin bytes.
nonisolated public struct PlacedDoor: Equatable, Sendable {
    public let reference: FormID
    public let position: SIMD3<Float>
    public let destination: PlacedReference.TeleportDestination

    public init(
        reference: FormID,
        position: SIMD3<Float>,
        destination: PlacedReference.TeleportDestination
    ) {
        self.reference = reference
        self.position = position
        self.destination = destination
    }
}
