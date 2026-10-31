// Script pins on loose bodies, such as a hanging key held to its peg
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

    /// - Returns: false when no pin joined the two.
    @discardableResult
    public mutating func removePins(_ first: PhysicsLinkEnd, _ second: PhysicsLinkEnd) -> Bool {
        let count = pins.count
        pins.removeAll { $0.joins(first, second) }
        return pins.count < count
    }

    mutating func holdPins(dt: Float) {
        for pin in pins {
            guard
                let index = bodies.firstIndex(where: { $0.key == pin.end.reference }),
                !bodies[index].isSleeping
            else { continue }
            pin.hold(&bodies[index], dt: dt)
        }
    }
}
