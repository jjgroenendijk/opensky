// The sort-and-sweep broad phase finds exactly the pairs the all-pairs loop found,
// in the same order.

import OpenSkyEngineTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyPhysics
import simd
import Testing

struct DynamicBodyBroadPhaseTests {
    private static func bruteForce(
        _ bodies: [DynamicBody],
        admits: (Int, Int) -> Bool
    ) -> [[Int]] {
        var pairs: [[Int]] = []
        for first in bodies.indices {
            for second in bodies.indices where second > first {
                guard admits(first, second) else { continue }
                guard !bodies[first].isSleeping || !bodies[second].isSleeping else { continue }
                let reach = bodies[first].definition.boundingRadius
                    + bodies[second].definition.boundingRadius
                guard
                    simd_distance_squared(bodies[first].position, bodies[second].position)
                    <= reach * reach
                else { continue }
                pairs.append([first, second])
            }
        }
        return pairs
    }

    /// A fixed scatter where many cubes overlap and every third one sleeps.
    private static func scatter() -> [DynamicBody] {
        (0 ..< 60).map { (index: Int) -> DynamicBody in
            let x: Int = index * 17 % 97
            let y: Int = index * 29 % 53
            let z: Int = index % 5 * 8
            var body = DynamicBodyScene.cube(
                key: .generated(UInt64(index + 1)),
                center: SIMD3<Float>(Float(x), Float(y), Float(z))
            )
            body.isSleeping = index % 3 == 0
            return body
        }
    }

    @Test func matchesTheAllPairsLoop() {
        let bodies = Self.scatter()
        let found = DynamicBodyBroadPhase.candidatePairs(bodies) { _, _ in true }
        let expected = Self.bruteForce(bodies) { _, _ in true }
        #expect(!expected.isEmpty)
        #expect(found.map { [$0.first, $0.second] } == expected)
    }

    @Test func appliesTheAdmitFilter() {
        let bodies = Self.scatter()
        let admits: (Int, Int) -> Bool = { ($0 + $1) % 2 == 0 }
        let found = DynamicBodyBroadPhase.candidatePairs(bodies, admits: admits)
        #expect(found.map { [$0.first, $0.second] } == Self.bruteForce(bodies, admits: admits))
    }

    @Test func allSleepingBodiesGiveNoPairs() {
        var bodies = Self.scatter()
        for index in bodies.indices {
            bodies[index].isSleeping = true
        }
        #expect(DynamicBodyBroadPhase.candidatePairs(bodies) { _, _ in true }.isEmpty)
    }

    @Test func aNonFiniteBodyIsLeftOut() {
        var bodies = [
            DynamicBodyScene.cube(key: .generated(1), center: .zero),
            DynamicBodyScene.cube(key: .generated(2), center: SIMD3(5, 0, 0)),
            DynamicBodyScene.cube(key: .generated(3), center: SIMD3(2, 0, 0))
        ]
        bodies[2].position = SIMD3(.nan, 0, 0)
        let found = DynamicBodyBroadPhase.candidatePairs(bodies) { _, _ in true }
        #expect(found.map { [$0.first, $0.second] } == [[0, 1]])
    }
}
