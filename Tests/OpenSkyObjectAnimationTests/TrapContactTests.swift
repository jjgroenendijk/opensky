// Trap contact: a moving bone near a capsule starts contact, repeats it at the interval,
// and stops it once the bone leaves; a bone at rest hits no one.

import OpenSkyFormatsESM
@testable import OpenSkyObjectAnimation
import Testing

struct TrapContactTests {
    private static let trap = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x10)
    private static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x20)
    private static let target = TrapContactTarget(
        key: actor, feet: [0, 0, 0], radius: 24, height: 128
    )
    private static let swinging = TrapContactPoint(position: [30, 0, 60], velocity: [500, 0, 0])

    @Test func contactStartsRepeatsAndStops() {
        var tracker = TrapContactTracker()
        let start = tracker.step(
            trap: Self.trap,
            points: [Self.swinging],
            targets: [Self.target],
            delta: 0.1
        )
        #expect(start == [.hit(
            trap: Self.trap,
            target: Self.actor,
            point: Self.swinging,
            initial: true
        )])
        let soon = tracker.step(
            trap: Self.trap,
            points: [Self.swinging],
            targets: [Self.target],
            delta: 0.1
        )
        #expect(soon.isEmpty)
        let repeated = tracker.step(
            trap: Self.trap,
            points: [Self.swinging],
            targets: [Self.target],
            delta: 0.2
        )
        #expect(repeated == [.hit(
            trap: Self.trap,
            target: Self.actor,
            point: Self.swinging,
            initial: false
        )])
        let far = TrapContactPoint(position: [500, 0, 60], velocity: [500, 0, 0])
        let stop = tracker.step(trap: Self.trap, points: [far], targets: [Self.target], delta: 0.1)
        #expect(stop == [.stop(trap: Self.trap, target: Self.actor)])
    }

    @Test func aBoneAtRestHitsNoOne() {
        var tracker = TrapContactTracker()
        let resting = TrapContactPoint(position: [30, 0, 60], velocity: .zero)
        #expect(tracker.step(trap: Self.trap, points: [resting], targets: [Self.target], delta: 0.1)
            .isEmpty)
    }

    @Test func velocitiesComeFromTheLastFrame() {
        var tracker = TrapContactTracker()
        let first = tracker.points(of: Self.trap, positions: [[0, 0, 0]], delta: 0.5)
        #expect(first.first?.velocity == .zero)
        let second = tracker.points(of: Self.trap, positions: [[10, 0, 0]], delta: 0.5)
        #expect(second.first?.velocity == [20, 0, 0])
    }
}
