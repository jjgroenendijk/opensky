import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyGameData
public import OpenSkyPhysics
public import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyWorldInterface
import OpenSkyWorldState
public import simd

/// The ground, seat, package walk, and collision the player moves through. Part of
/// `GameSessionPort`.
public protocol SessionMotionPort: AnyObject {
    var collisionQuery: CapsuleWorldCollider.CandidateQuery? { get }
    var playerSeat: float4x4? { get set }
    var playerWalkIgnoresStatics: Bool { get set }
    var playerWalkPath: [SIMD3<Float>] { get set }
    var terrainSampler: ((SIMD2<Float>) -> TerrainGroundSample?)? { get }
}
