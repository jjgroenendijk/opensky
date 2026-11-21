// The kill stats on the journal's Stats page (docs/engine/statistics.md, Combat).

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
}
