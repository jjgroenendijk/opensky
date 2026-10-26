// `openskycli game state nodes`: the placed meshes whose node controllers play on their
// own clock, such as a forge's look-at bellows (docs/engine/object-animation.md#node-controllers).

import OpenSkyAgentControl
import OpenSkyFormatsESM
import OpenSkyObjectAnimation
import simd

extension AgentWorldAdapter {
    /// Every mesh that plays node controllers, or one mesh's driven nodes.
    func nodesState(reference: String?) throws(AgentFailure) -> AgentJSON {
        let nodes = game.objectAnimationWorld.game.nodeControllers
        guard let reference else {
            return ["nodes": .array(nodes.references.map { ["ref": .formID($0)] })]
        }
        let target = try resolveReference(reference)
        guard let rows = nodes.nodes(of: target.formID.rawValue) else {
            throw AgentFailure(.notFound, "that reference plays no node controllers")
        }
        return ["ref": .formID(target.formID.rawValue), "nodes": .array(rows.map { row in
            let axis = row.rotation.act(SIMD3<Float>(1, 0, 0))
            return [
                "name": .string(row.name),
                "position": .init(row.translation),
                "forward": .init(axis),
                "rotationDegrees": .init(row.rotation.angle * 180 / .pi),
                "controllers": .array(row.controllers.map { .string($0) }),
                "active": .bool(row.isActive),
                "frozen": .bool(row.isFrozen)
            ]
        })]
    }
}
