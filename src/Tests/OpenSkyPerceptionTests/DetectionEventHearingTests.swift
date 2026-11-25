// Who checks a target's sound events, the scan for its flying projectiles, the shorter
// range for a fighter's other targets (docs/engine/detection-events.md).

import OpenSkyFormatsESM
@testable import OpenSkyPerception
@testable import OpenSkyPerceptionInterface
import simd
import Testing

struct DetectionEventHearingTests {
    private static let npc = ReferenceKey.generated(3)

    private static func observer(fighting: ReferenceKey? = nil) -> PerceptionObserver {
        var observer = PerceptionObserver(key: .generated(1), feet: .zero)
        observer.combatTarget = fighting
        return observer
    }

    @Test func aCalmObserverChecksOnlyWhenSomeoneFightsOrItIsAggressive() {
        var observer = Self.observer()
        var player = PerceptionTarget(key: .player, feet: SIMD3(100, 0, 0))
        #expect(!DetectionEventRule.checks(observer: observer, target: player))
        observer.isAggressive = true
        #expect(DetectionEventRule.checks(observer: observer, target: player))
        observer.isAggressive = false
        player.isInCombat = true
        #expect(DetectionEventRule.checks(observer: observer, target: player))
        observer.isFriendToPlayer = true
        #expect(!DetectionEventRule.checks(observer: observer, target: player))
        let npc = PerceptionTarget(key: Self.npc, feet: .zero)
        #expect(DetectionEventRule.checks(observer: Self.observer(fighting: .player), target: npc))
        #expect(!DetectionEventRule.checks(observer: Self.observer(), target: npc))
    }

    @Test func theNearestProjectileWithin1024UnitsIsScanned() {
        var player = PerceptionTarget(key: .player, feet: SIMD3(3000, 0, 0))
        player.projectiles = [SIMD3(900, 0, 0), SIMD3(500, 0, 0), SIMD3(2000, 0, 0)]
        #expect(DetectionEventRule.nearestProjectile(of: player, from: .zero) == SIMD3(500, 0, 0))
        var npc = PerceptionTarget(key: Self.npc, feet: .zero)
        npc.projectiles = [SIMD3(100, 0, 0)]
        #expect(DetectionEventRule.nearestProjectile(of: npc, from: .zero) == nil)
        npc.isInCombat = true
        #expect(DetectionEventRule.nearestProjectile(of: npc, from: .zero) == SIMD3(100, 0, 0))
    }

    @Test func aFighterChecksItsOtherTargetsAtThreeQuartersOfTheRange() {
        let fighter = Self.observer(fighting: .generated(9))
        #expect(DetectionEventRule.rangeShare(observer: fighter, target: Self.npc) == 0.75)
        #expect(DetectionEventRule.rangeShare(observer: fighter, target: .player) == 1)
        #expect(DetectionEventRule.rangeShare(observer: fighter, target: .generated(9)) == 1)
        #expect(DetectionEventRule.rangeShare(observer: Self.observer(), target: Self.npc) == 1)
    }
}
