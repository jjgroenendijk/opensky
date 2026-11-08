public import OpenSkyPhysics
public import OpenSkyRenderCore

/// The ground and collision one mount step runs against.
public struct MountStepWorld {
    public let sampleGround: (SIMD2<Float>) -> TerrainGroundSample?
    public let collisionQuery: CapsuleWorldCollider.CandidateQuery

    public init(
        sampleGround: @escaping (SIMD2<Float>) -> TerrainGroundSample?,
        collisionQuery: @escaping CapsuleWorldCollider.CandidateQuery
    ) {
        self.sampleGround = sampleGround
        self.collisionQuery = collisionQuery
    }
}
