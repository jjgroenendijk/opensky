// Warm starting: a contact starts each substep with the impulse it ended the last one
// with. Four iterations from zero could not hold a stack of five boxes; carried over,
// the impulses add up across substeps. See docs/engine/dynamic-narrowphase.md#warm-starting.

public import OpenSkyFormatsESM
import simd

/// One contact's impulses, kept on its body between substeps.
nonisolated struct DynamicWarmImpulse: Sendable {
    /// The contact point in the body's own frame.
    let localPoint: SIMD3<Float>
    let other: ReferenceKey?
    let isPatch: Bool
    let normal: Float
    /// The friction impulse in the body's own frame.
    let friction: SIMD3<Float>
}

nonisolated extension ContactSet {
    /// A contact this close, in the body's frame, to one of the last substep is the same.
    static let warmMatchDistance: Float = 2
    /// The share of the last impulse a contact starts with. Less than all of it, so a
    /// contact that matched the wrong one fades instead of pushing on.
    static let warmShare: Float = 0.9
}

nonisolated extension ContactSet {
    /// Seeds each contact with its match from the last substep and applies that impulse.
    mutating func warmStart(isPatch: Bool, bodies: inout [DynamicBody]) {
        for index in contacts.indices {
            let contact = contacts[index]
            let body = bodies[contact.body]
            guard !body.isSleeping else { continue }
            let other = contact.other.map { bodies[$0].key }
            let local = body.orientation.inverse.act(contact.point - body.position)
            let limit = Self.warmMatchDistance
            guard
                let match = body.warmImpulses.first(where: {
                    $0.isPatch == isPatch && $0.other == other
                        && simd_distance_squared($0.localPoint, local) <= limit * limit
                })
            else { continue }
            let share = Self.warmShare
            let normal = match.normal * share
            var friction = body.orientation.act(match.friction) * share
            friction -= contact.normal * simd_dot(friction, contact.normal)
            let cone = contact.friction * normal
            if simd_length(friction) > cone {
                friction = simd_length(friction) > Float.ulpOfOne
                    ? simd_normalize(friction) * cone : .zero
            }
            self.normal[index] = normal
            self.friction[index] = friction
            contact.apply(contact.normal * normal + friction, to: &bodies)
        }
    }

    func warmImpulses(isPatch: Bool, bodies: [DynamicBody]) -> [(Int, DynamicWarmImpulse)] {
        contacts.indices.compactMap { index in
            let contact = contacts[index]
            guard normal[index] > 0 else { return nil }
            let body = bodies[contact.body]
            let inverse = body.orientation.inverse
            return (contact.body, DynamicWarmImpulse(
                localPoint: inverse.act(contact.point - body.position),
                other: contact.other.map { bodies[$0].key },
                isPatch: isPatch,
                normal: normal[index],
                friction: inverse.act(friction[index])
            ))
        }
    }
}

nonisolated extension ContactSolveState {
    mutating func warmStart(bodies: inout [DynamicBody]) {
        patches.warmStart(isPatch: true, bodies: &bodies)
        points.warmStart(isPatch: false, bodies: &bodies)
    }

    /// Keeps this substep's impulses on their bodies. A sleeping body keeps none.
    func storeWarmImpulses(in bodies: inout [DynamicBody]) {
        var kept = [[DynamicWarmImpulse]](repeating: [], count: bodies.count)
        for (body, impulse) in patches.warmImpulses(isPatch: true, bodies: bodies)
            + points.warmImpulses(isPatch: false, bodies: bodies)
        {
            kept[body].append(impulse)
        }
        for index in bodies.indices {
            bodies[index].warmImpulses = bodies[index].isSleeping ? [] : kept[index]
        }
    }
}
