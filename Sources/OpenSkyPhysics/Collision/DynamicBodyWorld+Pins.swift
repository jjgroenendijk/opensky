// Script constraints on loose bodies: a pin, such as a hanging key held to its peg, a
// link to another loose body, and a link to a ragdoll bone
// (docs/engine/ragdoll-solver.md, "Script links").

import OpenSkyFormatsESM

nonisolated extension DynamicBodyWorld {
    /// Adds `pin` when its end names a simulated body. The node is not checked: a
    /// loose body is one rigid body.
    @discardableResult
    public mutating func addPin(_ pin: PhysicsPin) -> Bool {
        guard bodies.contains(where: { $0.key == pin.end.reference }) else { return false }
        removePins(pin.end, pin.partner)
        pins.append(pin)
        return true
    }

    /// Adds `link` when both ends name simulated bodies. Both wake.
    @discardableResult
    public mutating func addLink(_ link: PhysicsLink) -> Bool {
        guard
            let first = index(of: link.first.reference),
            let second = index(of: link.second.reference), first != second
        else { return false }
        removePins(link.first, link.second)
        links.append(link)
        bodies[first].wake()
        bodies[second].wake()
        return true
    }

    /// Adds a link from the loose body `link.first` to a ragdoll bone, `link.second`.
    /// The ragdoll world solves it (`RagdollWorld.solveLinks(to:frameTime:)`).
    @discardableResult
    public mutating func addRagdollLink(_ link: PhysicsLink) -> Bool {
        guard let first = index(of: link.first.reference) else { return false }
        removePins(link.first, link.second)
        ragdollLinks.append(link)
        bodies[first].wake()
        return true
    }

    /// Removes the pins and links between the two bodies, in either order.
    /// - Returns: false when nothing joined the two.
    @discardableResult
    public mutating func removePins(_ first: PhysicsLinkEnd, _ second: PhysicsLinkEnd) -> Bool {
        let count = pins.count + links.count + ragdollLinks.count
        pins.removeAll { $0.joins(first, second) }
        links.removeAll { $0.joins(first, second) }
        ragdollLinks.removeAll { $0.joins(first, second) }
        return pins.count + links.count + ragdollLinks.count < count
    }

    private func index(of key: ReferenceKey) -> Int? {
        bodies.firstIndex { $0.key == key }
    }

    mutating func holdPins(dt: Float) {
        for pin in pins {
            guard
                let index = bodies.firstIndex(where: { $0.key == pin.end.reference }),
                !bodies[index].isSleeping
            else { continue }
            pin.hold(&bodies[index], dt: dt)
        }
        for link in links {
            guard
                let first = index(of: link.first.reference),
                let second = index(of: link.second.reference),
                !(bodies[first].isSleeping && bodies[second].isSleeping)
            else { continue }
            bodies[first].wake()
            bodies[second].wake()
            var one = bodies[first]
            var other = bodies[second]
            link.solve(&one, &other, dt: dt)
            bodies[first] = one
            bodies[second] = other
        }
    }
}
