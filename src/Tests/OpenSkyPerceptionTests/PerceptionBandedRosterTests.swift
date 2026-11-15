// Far observers are built again less often than near ones; a new or departed observer
// is handled on the refresh it shows up in.

import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyPerception
@testable import OpenSkyPerceptionInterface
import simd
import Testing

@MainActor
struct PerceptionBandedRosterTests {
    private static let near = ReferenceKey.plugin(name: "perception.esm", objectID: 1)
    private static let far = ReferenceKey.plugin(name: "perception.esm", objectID: 2)
    private static let player = SIMD3<Float>(0, 0, 0)

    private static func candidate(
        _ key: ReferenceKey,
        at feet: SIMD3<Float>
    ) -> PerceptionCandidate {
        PerceptionCandidate(
            observer: PerceptionFixture.observer(key: key, feet: feet),
            isDead: false, isHostile: true, isEngaged: false, hasPackage: false
        )
    }

    /// 60 refreshes of 1/60 s: the near observer every time, the far one 5 times a second.
    @Test func aFarObserverIsBuiltAgainLessOften() {
        var roster = PerceptionBandedRoster()
        var builds: [ReferenceKey: Int] = [:]
        let feet = [Self.near: SIMD3<Float>(300, 0, 0), Self.far: SIMD3<Float>(9000, 0, 0)]
        for _ in 0 ..< 60 {
            roster.waited += 1.0 / 60
            var fresh: [PerceptionCandidate] = []
            for key in [Self.near, Self.far] {
                guard let position = feet[key] else { continue }
                if roster.isDue(key, feet: position, viewers: [Self.player]) {
                    builds[key, default: 0] += 1
                    fresh.append(Self.candidate(key, at: position))
                }
            }
            let listed = roster.apply((
                present: [Self.near, Self.far], fresh: fresh
            ))
            #expect(listed.map(\.observer.key) == [Self.near, Self.far])
        }
        #expect(builds[Self.near] == 60)
        #expect((5 ... 7).contains(builds[Self.far] ?? 0))
        #expect(roster.clocks[Self.far]?.band == .distant)
    }

    @Test func aDepartedObserverIsDropped() {
        var roster = PerceptionBandedRoster()
        roster.waited = 1.0 / 60
        _ = roster.isDue(Self.near, feet: .zero, viewers: [Self.player])
        _ = roster.apply((
            present: [Self.near], fresh: [Self.candidate(Self.near, at: .zero)]
        ))
        let listed = roster.apply((present: [], fresh: []))
        #expect(listed.isEmpty)
        #expect(roster.candidates.isEmpty)
        #expect(roster.clocks.isEmpty)
    }
}
