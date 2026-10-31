// `Game.AddHavokBallAndSocketConstraint` and `RemoveHavokConstraints` in the running
// game. Each end is a ragdoll bone, a loose body, or a node of a body that does not
// move; two ragdolls link, and a simulated end pins to a still one
// (docs/engine/papyrus-session-natives.md#havok-constraints).

import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import simd

extension ScriptWorldAdapter {
    private enum ConstraintBody {
        case ragdoll
        case loose
        case still
        /// A living actor that is not ragdolling takes no constraint.
        case unavailable
    }

    func addBallAndSocket(
        _ first: PhysicsLinkEnd, _ second: PhysicsLinkEnd
    ) -> PapyrusNativeResult {
        guard let runtime = game.ragdoll.runtime else { return .returned(.boolean(false)) }
        switch (body(of: first, runtime), body(of: second, runtime)) {
        case (.ragdoll, .ragdoll):
            return .returned(.boolean(runtime.addLink(RagdollLink(first: first, second: second))))
        case (.ragdoll, .still), (.loose, .still):
            return pin(first, to: second)
        case (.still, .ragdoll), (.still, .loose):
            return pin(second, to: first)
        default:
            return .returned(.boolean(false))
        }
    }

    func removeConstraints(_ first: PhysicsLinkEnd, _ second: PhysicsLinkEnd) -> Bool {
        let ragdolls = game.ragdoll.runtime?.removeConstraints(first, second) ?? false
        let loose = game.streamer?.dynamicBodies.removePins(first, second) ?? false
        return ragdolls || loose
    }

    private func body(of end: PhysicsLinkEnd, _ runtime: RagdollRuntime) -> ConstraintBody {
        if game.streamer?.dynamicBodies.body(for: end.reference) != nil {
            return .loose
        }
        if game.actorWorld.actorValueHolder(for: end.reference) != nil {
            return runtime.ragdollsForConstraint(end.reference) ? .ragdoll : .unavailable
        }
        return .still
    }

    /// Pins `end` where `anchor`'s node and offset sit, once that model is read.
    private func pin(_ end: PhysicsLinkEnd, to anchor: PhysicsLinkEnd) -> PapyrusNativeResult {
        guard let nodes = modelNodes else { return .returned(.boolean(false)) }
        let place: (simd_float4x4?) -> PapyrusValue = { [weak self] node in
            guard let self, let node else { return .boolean(false) }
            let point = node * SIMD4(anchor.offset, 1)
            let pin = PhysicsPin(end: end, partner: anchor, point: SIMD3(point.x, point.y, point.z))
            let pinned = game.streamer?.dynamicBodies.body(for: end.reference) != nil
                ? game.streamer?.dynamicBodies.addPin(pin) ?? false
                : game.ragdoll.runtime?.addPin(pin) ?? false
            return .boolean(pinned)
        }
        switch nodeTransform(of: anchor.reference, named: anchor.node, nodes: nodes, then: place) {
        case let .found(node): return .returned(place(node))
        case .missing: return .returned(.boolean(false))
        case let .loading(token): return .suspended(.external(token))
        }
    }
}
