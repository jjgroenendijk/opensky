public import OpenSkyCells
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyPhysics
import OpenSkyRendering
public import OpenSkyScripting
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
public import OpenSkyWorldState
import simd

/// What `ScriptPhysicsBindingsAdapter` reads from the session.
@MainActor
public protocol ScriptPhysicsBindingsHost: AnyObject {
    var actorWorld: any ActorWorldPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var ragdoll: any RagdollPort { get }
    var streamer: (any CellStreamerPort)? { get }
    var worldData: WorldDataStores? { get }
}

/// Part of `ScriptWorldAdapter`, over its own narrow host.
public struct ScriptPhysicsBindingsAdapter {
    public let game: any ScriptPhysicsBindingsHost
    public let state: ScriptPartState
    public let nodeBindings: ScriptNodeBindingsAdapter
}

extension ScriptPhysicsBindingsAdapter {
    private enum ConstraintBody {
        case ragdoll
        case loose
        case still
        /// A living actor that is not ragdolling takes no constraint.
        case unavailable
    }

    public func addBallAndSocket(
        _ first: PhysicsLinkEnd, _ second: PhysicsLinkEnd
    ) -> PapyrusNativeResult {
        guard let runtime = game.ragdoll.runtime else { return .returned(.boolean(false)) }
        switch (body(of: first, runtime), body(of: second, runtime)) {
        case (.ragdoll, .ragdoll):
            return .returned(.boolean(runtime.addLink(PhysicsLink(first: first, second: second))))
        case (.loose, .loose):
            let linked = game.streamer?.dynamicBodies
                .addLink(PhysicsLink(first: first, second: second)) ?? false
            return .returned(.boolean(linked))
        case (.loose, .ragdoll), (.ragdoll, .loose):
            return linkLoose(first, second, runtime)
        case (.ragdoll, .still), (.loose, .still):
            return pin(first, to: second)
        case (.still, .ragdoll), (.still, .loose):
            return pin(second, to: first)
        default:
            return .returned(.boolean(false))
        }
    }

    public func removeConstraints(_ first: PhysicsLinkEnd, _ second: PhysicsLinkEnd) -> Bool {
        let ragdolls = game.ragdoll.runtime?.removeConstraints(first, second) ?? false
        let loose = game.streamer?.dynamicBodies.removePins(first, second) ?? false
        return ragdolls || loose
    }

    /// A loose body held to a ragdoll bone. The bone must have a body.
    private func linkLoose(
        _ first: PhysicsLinkEnd, _ second: PhysicsLinkEnd, _ runtime: any RagdollRuntimePort
    ) -> PapyrusNativeResult {
        let looseFirst = game.streamer?.dynamicBodies.body(for: first.reference) != nil
        let link = looseFirst
            ? PhysicsLink(first: first, second: second) : PhysicsLink(first: second, second: first)
        guard runtime.hasBody(link.second) else { return .returned(.boolean(false)) }
        let linked = game.streamer?.dynamicBodies.addRagdollLink(link) ?? false
        return .returned(.boolean(linked))
    }

    private func body(of end: PhysicsLinkEnd, _ runtime: any RagdollRuntimePort) -> ConstraintBody {
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
        guard let nodes = state.modelNodes else { return .returned(.boolean(false)) }
        let place: (simd_float4x4?) -> PapyrusValue = { node in
            guard let node else { return .boolean(false) }
            let point = node * SIMD4(anchor.offset, 1)
            let pin = PhysicsPin(end: end, partner: anchor, point: SIMD3(point.x, point.y, point.z))
            let pinned = game.streamer?.dynamicBodies.body(for: end.reference) != nil
                ? game.streamer?.dynamicBodies.addPin(pin) ?? false
                : game.ragdoll.runtime?.addPin(pin) ?? false
            return .boolean(pinned)
        }
        switch nodeBindings.nodeTransform(
            of: anchor.reference,
            named: anchor.node,
            nodes: nodes,
            then: place
        ) {
        case let .found(node): return .returned(place(node))
        case .missing: return .returned(.boolean(false))
        case let .loading(token): return .suspended(.external(token))
        }
    }

    /// Draws each running move and lets it push the loose bodies in its way.
    public func publishTranslations(
        _ poses: [ReferenceKey: ReferenceTransformOverride],
        moves: [ReferenceKey: PapyrusTranslation]
    ) {
        pushLooseBodies(by: moves)
        game.gameSession?.instancePoses.scriptedPoses = poses
            .reduce(into: [:]) { matrices, entry in
                guard let formID = game.streamer?.referenceEntry(key: entry.key)?.formID
                else { return }
                matrices[formID.rawValue] = MatrixMath.placement(
                    position: entry.value.position, rotation: entry.value.rotation, scale: 1
                )
            }
    }

    public func pushLooseBodies(by translations: [ReferenceKey: PapyrusTranslation]) {
        guard
            let streamer = game.streamer, streamer.dynamicBodies.bodyCount > 0,
            let keywords = game.worldData?.locationStore?.keywords
        else { return }
        for key in translations.keys.sorted() {
            guard
                let move = translations[key], move.velocity != .zero,
                let base = streamer.referenceEntry(key: key)?.placedReference?.base,
                let id = keywords.resolvedID(base, fromPlugin: FormIDResolver.loadOrderSpaceName),
                let bounds = keywords.bounds(of: id), !bounds.isEmpty
            else { continue }
            let scale = streamer.referenceEntry(key: key)?.placedReference?.scale ?? 1
            streamer.dynamicBodies.push(by: ScriptedMover(
                placement: MatrixMath.placement(
                    position: move.position, rotation: move.rotation, scale: 1
                ),
                minimum: SIMD3<Float>(bounds.minimum) * scale,
                maximum: SIMD3<Float>(bounds.maximum) * scale,
                velocity: move.velocity
            ))
        }
    }
}
