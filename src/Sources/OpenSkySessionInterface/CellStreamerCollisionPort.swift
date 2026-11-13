// Ground, water, and collision queries against the resident cells.

public import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyPhysics
public import OpenSkyRenderCore
import OpenSkyRendering
public import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// Ground, water, and collision queries against the resident cells. Part of `CellStreamerPort`.
public protocol CellStreamerCollisionPort {
    func collisionCandidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape]
    func nearestCollisionHit(ray: InteractionRay) -> InteractionRayHit?
    func sampleTerrain(at position: SIMD2<Float>) -> TerrainGroundSample?
    func sampleWaterHeight(at position: SIMD2<Float>) -> Float?
    func staticCollisionBlocks(ray: InteractionRay) -> Bool
    func staticCollisionCandidates(overlapping bounds: ModelBounds) -> [StaticCollisionShape]
    func topCollisionSurface(at position: SIMD2<Float>) -> SIMD3<Float>?
    func water(at point: SIMD3<Float>) -> WaterReading?
}
