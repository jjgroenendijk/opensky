// The kill stats on the journal's Stats page (docs/engine/statistics.md, Combat).

import OpenSkyActorsInterface
import OpenSkyCombat
import Testing

struct KillStatsTests {
    private static func stats(_ keywords: Set<String>) -> [String] {
        KillStats.stats { keywords.contains($0) }
    }

    @Test func eachActorTypeRaisesItsOwnStat() {
        #expect(Self.stats(["ActorTypeNPC"]) == ["People Killed"])
        #expect(Self.stats(["ActorTypeAnimal", "ActorTypeCreature"]) == ["Animals Killed"])
        #expect(Self.stats(["ActorTypeUndead", "ActorTypeCreature"]) == ["Undead Killed"])
        #expect(Self.stats(["ActorTypeDaedra", "ActorTypeCreature"]) == [
            "Daedra Killed", "Creatures Killed"
        ])
        #expect(Self.stats(["ActorTypeDwarven"]) == ["Automatons Killed"])
        #expect(Self.stats(["ActorTypeCreature"]) == ["Creatures Killed"])
        #expect(Self.stats([]).isEmpty)
    }

    @Test func anUndeadPersonCountsAsBoth() {
        #expect(Self.stats(["ActorTypeNPC", "ActorTypeUndead"]) == [
            "People Killed", "Undead Killed"
        ])
    }

    @Test func aBeastFormKillMaulsAndARabbitCountsAsABunny() {
        let rabbit = KillStats.stats(
            hasKeyword: { $0 == "ActorTypeAnimal" }, isBunny: true, inBeastForm: true
        )
        #expect(rabbit == ["Mauls", "Bunnies Slaughtered", "Animals Killed"])
    }
}

/// docs/engine/statistics.md, Critical hits.
struct CriticalHitStatsTests {
    @Test func aCriticalDaggerSneakAttackCountsTwoBackstabs() {
        let stats = CriticalHitStats.stats(
            critical: true, sneakAttack: true, handType: .dagger, ownsSneakAttackPerk: true
        )
        #expect(stats.count { $0 == "Critical Strikes" } == 2)
        #expect(stats.count { $0 == "Sneak Attacks" } == 1)
        #expect(stats.count { $0 == "Backstabs" } == 2)
    }

    @Test func aBowNeverBackstabsAndAPlainHitCountsNothing() {
        let bow = CriticalHitStats.stats(
            critical: false, sneakAttack: true, handType: .bow, ownsSneakAttackPerk: true
        )
        #expect(bow == ["Critical Strikes", "Sneak Attacks"])
        let sword = CriticalHitStats.stats(
            critical: true, sneakAttack: false, handType: .sword, ownsSneakAttackPerk: false
        )
        #expect(sword == ["Critical Strikes"])
        #expect(CriticalHitStats.stats(
            critical: false, sneakAttack: false, handType: .sword, ownsSneakAttackPerk: true
        ).isEmpty)
    }
}
