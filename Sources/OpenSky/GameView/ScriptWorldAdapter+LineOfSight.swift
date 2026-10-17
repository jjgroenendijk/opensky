// The `seesTarget` seam behind the Papyrus `RegisterForLOS` family. The player sees what
// is inside the camera's view with no static collision between; an NPC sees what its
// detection pair says. See docs/engine/papyrus-registrations.md#line-of-sight.

import OpenSkyFormatsESM
import OpenSkyPerception
import OpenSkyPerceptionInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyWorldState
import simd

extension ScriptWorldAdapter {
    /// How far short of the target the trace stops, so the target's own collision
    /// does not hide it. About half a metre.
    private static let traceMargin: Float = 32

    func wireLineOfSight(bridge: PapyrusWorldStateBridge) {
        bridge.perceptionNatives.seesTarget = { [weak self] viewer, target in
            self?.sees(viewer: viewer, target: target, bridge: bridge)
        }
    }

    private func sees(
        viewer: ReferenceKey, target: ReferenceKey, bridge: PapyrusWorldStateBridge
    ) -> Bool? {
        guard viewer == .player else {
            return game.perception.perceptionResolution()
                .pair(observer: viewer, target: target)?.hasLineOfSight
        }
        guard let renderer = game.renderer, let point = position(of: target, bridge: bridge)
        else { return nil }
        let projection = renderer.projectionMatrix
        guard projection.columns.0.x > 0, projection.columns.1.y > 0 else { return nil }
        let camera = renderer.freeFlyCamera
        let view = LineOfSightWatch.View(
            forward: camera.forward, right: camera.right,
            up: simd_normalize(simd_cross(camera.right, camera.forward)),
            tanHalfWidth: 1 / projection.columns.0.x, tanHalfHeight: 1 / projection.columns.1.y
        )
        let offset = point - camera.position
        guard view.contains(offset) else { return false }
        let distance = simd_length(offset)
        guard distance > Self.traceMargin else { return true }
        let end = camera.position + offset * ((distance - Self.traceMargin) / distance)
        return game.aiWorld.perceptionHasLineOfSight(from: camera.position, to: end)
    }

    /// An actor's chest, or a placed object's origin.
    private func position(
        of key: ReferenceKey, bridge: PapyrusWorldStateBridge
    ) -> SIMD3<Float>? {
        if let feet = bridge.perceptionNatives.livePosition?(key) {
            return feet + SIMD3(0, 0, PlayerCapsule.standard.eyeHeight / 2)
        }
        return bridge.placement(of: key)?.state.transform.position
    }
}
