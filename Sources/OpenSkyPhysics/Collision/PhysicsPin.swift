// A simulated body held at a fixed world point, as a script constraint to a body
// that does not move: a rope's joint helper, or a peg's dummy node. The point acts as
// a body too heavy to move, so the ragdoll joint solver can hold it
// (docs/engine/ragdoll-solver.md, "Script links").

import OpenSkyFormatsESM
import simd

/// One end of a script constraint: a reference, a node of its 3D, and a pivot in
/// that node's body space, in engine units.
nonisolated public struct PhysicsLinkEnd: Equatable, Sendable {
    public let reference: ReferenceKey
    public let node: String
    public let offset: SIMD3<Float>

    public init(reference: ReferenceKey, node: String, offset: SIMD3<Float> = .zero) {
        self.reference = reference
        self.node = node
        self.offset = offset
    }

    func names(_ other: PhysicsLinkEnd) -> Bool {
        reference == other.reference && node.lowercased() == other.node.lowercased()
    }

    static func pair(
        _ first: PhysicsLinkEnd, _ second: PhysicsLinkEnd, is one: PhysicsLinkEnd,
        _ other: PhysicsLinkEnd
    ) -> Bool {
        (first.names(one) && second.names(other)) || (first.names(other) && second.names(one))
    }
}

/// `end` held at `point`. `partner` is the fixed body's own end, kept so a script
/// can remove the constraint by naming both bodies.
nonisolated public struct PhysicsPin: Equatable, Sendable {
    public let end: PhysicsLinkEnd
    public let partner: PhysicsLinkEnd
    public let point: SIMD3<Float>

    public init(end: PhysicsLinkEnd, partner: PhysicsLinkEnd, point: SIMD3<Float>) {
        self.end = end
        self.partner = partner
        self.point = point
    }

    func joins(_ one: PhysicsLinkEnd, _ other: PhysicsLinkEnd) -> Bool {
        PhysicsLinkEnd.pair(end, partner, is: one, other)
    }

    private static let anchor = DynamicBodyDefinition(
        volumes: [.radial(first: .zero, second: .zero, radius: 1)], mass: 1e12
    )

    /// One substep of holding `body`'s pivot at the point.
    func hold(_ body: inout DynamicBody, dt: Float) {
        var bodies = [
            body,
            DynamicBody(
                key: body.key, reference: body.reference, cell: body.placingCell,
                definition: Self.anchor, originPosition: point, orientation: .identityRotation
            )
        ]
        RagdollConstraintSolver.solve(
            joints: [RagdollJointDefinition(
                bodyA: 0, bodyB: 1,
                frameA: RagdollJointFrame.pivot(end.offset - body.definition.centerOfMass),
                frameB: RagdollJointFrame.identity, limits: .point
            )],
            bodies: &bodies, dt: dt
        )
        body = bodies[0]
    }
}

nonisolated extension RagdollJointFrame {
    /// A ball-and-socket end: only the pivot matters.
    static func pivot(_ pivot: SIMD3<Float>) -> RagdollJointFrame {
        RagdollJointFrame(
            pivot: pivot, primaryAxis: identity.primaryAxis, secondaryAxis: identity.secondaryAxis
        )
    }
}
