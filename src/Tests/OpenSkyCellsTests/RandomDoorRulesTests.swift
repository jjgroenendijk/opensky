// The random choices of a random door: every destination tried once, a pick from
// the candidates, and the landing in front of a door.

@testable import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import simd
import Testing

struct RandomDoorRulesTests {
    @Test func everyDestinationIsTriedOnce() {
        var random = SplitMix64(seed: 7)
        let order = RandomDoorRules.tryOrder([1, 2, 3, 4, 5], using: &random)
        #expect(order.sorted() == [1, 2, 3, 4, 5])
    }

    @Test func theSameSeedTriesTheSameOrder() {
        var first = SplitMix64(seed: RandomDoorRules.seed(door: FormID(0x300), sequence: 4))
        var second = SplitMix64(seed: RandomDoorRules.seed(door: FormID(0x300), sequence: 4))
        #expect(RandomDoorRules.tryOrder(Array(0 ..< 8), using: &first)
            == RandomDoorRules.tryOrder(Array(0 ..< 8), using: &second))
    }

    @Test func noCandidatePicksNothing() {
        var random = SplitMix64(seed: 1)
        #expect(RandomDoorRules.pick([Int](), using: &random) == nil)
        #expect(RandomDoorRules.pick([9], using: &random) == 9)
    }

    @Test func thePlayerLandsInFrontOfTheDoorFacingAway() {
        let door = PlacedReference.Placement(
            position: SIMD3(100, 100, 50), rotation: SIMD3(0, 0, 0)
        )
        let landing = RandomDoorRules.landing(before: door)
        #expect(simd_distance(landing.position, SIMD3(100, 250, 50)) < 0.001)
        #expect(landing.rotation.z == 0)
    }
}
