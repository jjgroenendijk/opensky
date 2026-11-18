// The walk controller's contact state, for `state player` `walk`: what holds the feet up,
// the swim state, and the terrain under and just ahead of the feet.
// See docs/engine/ground-and-water-contact.md.

import OpenSkyAgentControl
import OpenSkyPhysics
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkySessionInterface
import simd

extension AgentPlayerStatusReadout {
    /// How far ahead of the feet, along the view, the terrain is also read.
    static let terrainAheadDistance: Float = 24

    func walkState(gameSession: any GameSessionPort) -> AgentJSON {
        let walk = gameSession.walkController
        let feet = walk.feetPosition
        let yaw = gameSession.freeFlyCamera.yaw
        let ahead = SIMD2(feet.x, feet.y)
            + SIMD2(cosf(yaw), sinf(yaw)) * Self.terrainAheadDistance
        let sample = gameSession.terrainSampler
        return [
            "feet": .init(feet),
            "grounded": .bool(walk.isGrounded),
            "swimming": .bool(walk.isSwimming),
            "verticalVelocity": .init(walk.verticalVelocity),
            "groundNormal": walk.groundNormal.map { .init($0) } ?? .null,
            "stepSupport": walk.activeStepSupport.map { .init($0.height) } ?? .null,
            "heldAtEdge": .bool(walk.isHeldAtEdge),
            "unresolvedPenetration": .bool(walk.hasUnresolvedPenetration),
            "terrain": Self.terrainState(sample?(SIMD2(feet.x, feet.y))),
            "terrainAhead": Self.terrainState(sample?(ahead))
        ]
    }

    private static func terrainState(_ sample: TerrainGroundSample?) -> AgentJSON {
        guard let sample else { return .null }
        return ["height": .init(sample.height), "normal": .init(sample.normal)]
    }
}
