// Script constraints on ragdolls, as `Game.AddHavokBallAndSocketConstraint` adds them:
// a link holds a pivot on two ragdolls' bones together, and a pin holds a bone at a
// fixed point. Rotation stays free. A ragdoll that stops simulating drops both
// (docs/engine/ragdoll-solver.md, "Script links").

import Foundation
import OpenSkyFormatsESM
import simd

nonisolated public struct RagdollLink: Equatable, Sendable {
    public let first: PhysicsLinkEnd
    public let second: PhysicsLinkEnd

    public init(first: PhysicsLinkEnd, second: PhysicsLinkEnd) {
        self.first = first
        self.second = second
    }

    func joins(_ one: PhysicsLinkEnd, _ other: PhysicsLinkEnd) -> Bool {
        PhysicsLinkEnd.pair(first, second, is: one, other)
    }
}

nonisolated extension RagdollWorld {
    /// Adds `link` when both ends name a bone body of a live ragdoll. A link between
    /// the same two bones replaces the old one. Both ragdolls wake.
    @discardableResult
    public mutating func addLink(_ link: RagdollLink) -> Bool {
        guard
            let first = body(of: link.first), let second = body(of: link.second),
            first != second
        else { return false }
        removeLinks(link.first, link.second)
        links.append(link)
        ragdolls[first.ragdoll].instance.wake()
        ragdolls[second.ragdoll].instance.wake()
        return true
    }

    /// Adds `pin` when its end names a bone body of a live ragdoll, which wakes.
    @discardableResult
    public mutating func addPin(_ pin: PhysicsPin) -> Bool {
        guard let body = body(of: pin.end) else { return false }
        removeLinks(pin.end, pin.partner)
        pins.append(pin)
        ragdolls[body.ragdoll].instance.wake()
        return true
    }

    /// Removes the links and pins between the two bodies, in either order.
    /// - Returns: false when there was none.
    @discardableResult
    public mutating func removeLinks(_ first: PhysicsLinkEnd, _ second: PhysicsLinkEnd) -> Bool {
        let count = links.count + pins.count
        links.removeAll { $0.joins(first, second) }
        pins.removeAll { $0.joins(first, second) }
        return links.count + pins.count < count
    }

    mutating func dropConstraints(of key: ReferenceKey) {
        links.removeAll { $0.first.reference == key || $0.second.reference == key }
        pins.removeAll { $0.end.reference == key }
    }

    mutating func solveLinks(dt: Float) {
        for pin in pins {
            guard let index = body(of: pin.end) else { continue }
            pin.hold(&ragdolls[index.ragdoll].instance.bodies[index.bone], dt: dt)
        }
        for link in links {
            guard let first = body(of: link.first), let second = body(of: link.second) else {
                continue
            }
            var bodies = [
                ragdolls[first.ragdoll].instance.bodies[first.bone],
                ragdolls[second.ragdoll].instance.bodies[second.bone]
            ]
            RagdollConstraintSolver.solve(
                joints: [RagdollJointDefinition(
                    bodyA: 0, bodyB: 1,
                    frameA: .pivot(link.first.offset - bodies[0].definition.centerOfMass),
                    frameB: .pivot(link.second.offset - bodies[1].definition.centerOfMass),
                    limits: .point
                )],
                bodies: &bodies, dt: dt
            )
            ragdolls[first.ragdoll].instance.bodies[first.bone] = bodies[0]
            ragdolls[second.ragdoll].instance.bodies[second.bone] = bodies[1]
        }
    }

    private struct BodyIndex: Equatable {
        let ragdoll: Int
        let bone: Int
    }

    private func body(of end: PhysicsLinkEnd) -> BodyIndex? {
        guard
            let ragdoll = ragdolls.firstIndex(where: { $0.key == end.reference }),
            let bone = ragdolls[ragdoll].instance.definition.bones.firstIndex(where: {
                $0.boneName.caseInsensitiveCompare(end.node) == .orderedSame
            }),
            ragdolls[ragdoll].instance.bodies.indices.contains(bone)
        else { return nil }
        return BodyIndex(ragdoll: ragdoll, bone: bone)
    }
}
