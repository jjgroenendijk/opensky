// `Game.AddHavokBallAndSocketConstraint` and `Game.RemoveHavokConstraints`: a pivot
// on one reference's rigid body held to a pivot on another's. The app answers them
// with ragdoll links and pins, so a live actor takes one only while it ragdolls (CK
// wiki pages of both functions; docs/engine/papyrus-session-natives.md).

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

/// One end of a script constraint: a reference, the node of its rigid body, and an
/// offset in that body's own space.
nonisolated public struct PapyrusConstraintEnd: Equatable, Sendable {
    public let reference: ReferenceKey
    public let node: String
    public let offset: SIMD3<Float>

    public init(reference: ReferenceKey, node: String, offset: SIMD3<Float> = .zero) {
        self.reference = reference
        self.node = node
        self.offset = offset
    }
}

extension PapyrusNativeFunctions {
    static func installHavokConstraints(into registry: inout PapyrusNativeRegistry) {
        constraintHook("AddHavokBallAndSocketConstraint", into: &registry) { call, ends, hooks in
            let offsets = (4 ..< 10).map { float(call, at: $0) ?? 0 }
            let first = PapyrusConstraintEnd(
                reference: ends.0.reference, node: ends.0.node,
                offset: SIMD3(offsets[0], offsets[1], offsets[2])
            )
            let second = PapyrusConstraintEnd(
                reference: ends.1.reference, node: ends.1.node,
                offset: SIMD3(offsets[3], offsets[4], offsets[5])
            )
            return hooks.addBallAndSocket.map { $0(first, second) }
        }
        constraintHook("RemoveHavokConstraints", into: &registry) { _, ends, hooks in
            hooks.removeConstraints.map { .returned(.boolean($0(ends.0, ends.1))) }
        }
    }

    /// Reads the two references and node names both natives start with. A missing
    /// reference answers false, as a constraint that cannot exist.
    private static func constraintHook(
        _ name: String, into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, (PapyrusConstraintEnd, PapyrusConstraintEnd), PapyrusGameNatives
        ) -> PapyrusNativeResult?
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "Game", functionName: name
        ) { call, context in
            guard let bridge = context.world as? PapyrusWorldStateBridge else {
                return needsWorld(call)
            }
            guard
                let first = objectArgument(call, at: 0).flatMap(bridge.referenceKey(for:)),
                let second = objectArgument(call, at: 2).flatMap(bridge.referenceKey(for:))
            else { return .returned(.boolean(false)) }
            let ends = (
                PapyrusConstraintEnd(reference: first, node: string(call, at: 1) ?? ""),
                PapyrusConstraintEnd(reference: second, node: string(call, at: 3) ?? "")
            )
            return body(call, ends, bridge.gameNatives)
                ?? failure(call, "\(call.qualifiedName) needs the running game")
        })
    }
}
