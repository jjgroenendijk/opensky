// The world AABB of a scene's sun-shadow casters, split by whether a caster can move.
// The fixed part is built once per scene; only movable casters merge in per frame.

import OpenSkyFormatsCore

nonisolated public struct ShadowCasterBounds: Sendable {
    /// Union of every caster no body or NPC can move, terrain included.
    public let fixed: ModelBounds?
    /// Casters with a reference a live pose can move; they merge at that pose.
    public let movable: [DrawInstance]
    /// Some caster has no bounds, so the union cannot clamp anything.
    public let isUnbounded: Bool

    public init(scene: RenderScene) {
        var fixed: ModelBounds?
        var movable: [DrawInstance] = []
        var isUnbounded = false
        let groups = scene.opaque + scene.alphaTested
        for group in groups where group.castsShadows {
            for instance in group.instances {
                if instance.referenceFormID != 0 {
                    movable.append(instance)
                } else if let bounds = instance.bounds {
                    fixed = fixed.map { $0.union(bounds) } ?? bounds
                } else {
                    isUnbounded = true
                }
            }
        }
        for item in scene.terrain {
            guard let bounds = item.bounds else {
                isUnbounded = true
                continue
            }
            fixed = fixed.map { $0.union(bounds) } ?? bounds
        }
        self.fixed = fixed
        self.movable = movable
        self.isUnbounded = isUnbounded
    }
}
