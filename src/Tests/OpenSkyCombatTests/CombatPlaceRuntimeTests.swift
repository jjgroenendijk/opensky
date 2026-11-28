// The runtime's places around a target: two styled fighters book arcs that do not
// overlap, and a failed advance path leads to the surround.
// Rules: docs/engine/combat-movement.md.

import OpenSkyActorsInterface
@testable import OpenSkyCombat
import OpenSkyCombatFixtures
@testable import OpenSkyCombatInterface
import simd
import Testing

@MainActor
struct CombatPlaceRuntimeTests {
    private static let opponent = CombatLoopFixture.opponent
    private static let second = CombatLoopFixture.second

    @Test func twoStyledFightersBookTwoPlacesAroundThePlayer() {
        let (runtime, world) = CombatLoopFixture.session()
        world.actors.append(.init(key: Self.second, feet: SIMD3(60, 10, 0), name: "Second"))
        world.weapons[Self.second] = world.weapons[Self.opponent]
        for key in [Self.opponent, Self.second] {
            var style = CombatStyleTuning.neutral
            style.offensiveMultiplier = 0
            world.styles[key] = style
            CombatLoopFixture.engage(runtime, world, key)
        }
        CombatLoopFixture.run(runtime, seconds: 1)
        let book = runtime.places[world.player.key]
        #expect(book?.arcs.count == 2)
        let first = runtime.placeDegrees(of: Self.opponent)
        let other = runtime.placeDegrees(of: Self.second)
        #expect(first != nil && other != nil && first != other)
        runtime.setHostility(.neutral, on: Self.second)
        runtime.parkBehavior(of: Self.second)
        CombatLoopFixture.run(runtime, seconds: 0.1)
        #expect(runtime.places[world.player.key]?.arcs.count == 1)
    }

    @Test func aStyledFighterWithNoPathSurroundsOrCircles() {
        let (runtime, world) = CombatLoopFixture.session(feet: SIMD3(2000, 0, 0))
        world.styles[Self.opponent] = .neutral
        world.movementSucceeds = false
        CombatLoopFixture.engage(runtime, world)
        CombatLoopFixture.run(runtime, seconds: 3)
        #expect((runtime.behaviors[Self.opponent]?.pathMoveCount ?? 0) >= 1)
    }
}
