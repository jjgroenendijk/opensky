// The pair order is kept while the same actors stay. Positions still refresh
// every frame, and an actor that arrives or leaves rebuilds the order.

import OpenSkyFeaturesTesting
import OpenSkyFormatsESM
@testable import OpenSkyPerception
@testable import OpenSkyPerceptionInterface
import simd
import Testing

@MainActor
extension PerceptionRuntimeTests {
    @Test func aTargetThatMovesBehindAWallReadsTheNewPosition() {
        let world = FakePerceptionWorld(
            observers: [PerceptionFixture.observer(feet: SIMD3(0, 0, 0))],
            targets: [PerceptionFixture.target(feet: SIMD3(100, 0, 0))],
            blocked: PerceptionFixture.wall(atX: 200)
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 30)
        #expect(runtime.state(observer: PerceptionFixture.guardKey, target: .player).hasLineOfSight)

        world.targets = [PerceptionFixture.target(feet: SIMD3(400, 0, 0))]
        advance(runtime, steps: 30)
        let pair = runtime.state(observer: PerceptionFixture.guardKey, target: .player)
        #expect(!pair.hasLineOfSight)
        #expect(abs(pair.distance - 400) < 1)
    }

    @Test func anArrivingObserverGetsAPairAndALeavingOneLosesIt() {
        let first = PerceptionFixture.observer(feet: SIMD3(0, 0, 0))
        let second = PerceptionFixture.observer(
            key: PerceptionFixture.secondGuardKey, feet: SIMD3(0, 50, 0), name: "Second"
        )
        let world = FakePerceptionWorld(
            observers: [first],
            targets: [PerceptionFixture.target(feet: SIMD3(100, 0, 0))]
        )
        let runtime = PerceptionRuntime(settings: settings, world: world)
        advance(runtime, steps: 30)
        #expect(Set(runtime.pairs.keys.map(\.observer)) == [PerceptionFixture.guardKey])

        world.observers = [first, second]
        advance(runtime, steps: 30)
        #expect(
            Set(runtime.pairs.keys.map(\.observer))
                == [PerceptionFixture.guardKey, PerceptionFixture.secondGuardKey]
        )

        world.observers = [second]
        advance(runtime, steps: 30)
        #expect(Set(runtime.pairs.keys.map(\.observer)) == [PerceptionFixture.secondGuardKey])
    }
}
