import Foundation
@testable import OpenSkyActors
@testable import OpenSkyActorsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ActorValueRaceRegenerationTests {
    /// A troll's race keeps full health regeneration in combat; others take
    /// `fCombatHealthRegenRateMult`, 0 in vanilla.
    @Test func aRaceFlagKeepsHealthRegenerationInCombat() {
        var settings = RegenerationSettings.vanilla
        settings.healthDelay = 0
        var troll = ActorValueBaseline(
            maximums: ActorValues(repeating: 100), regenPercentPerSecond: ActorValues(repeating: 6)
        )
        troll.regeneratesHealthInCombat = true
        let runtime = ActorValueRuntime(
            store: WorldStateStore(), baselines: ActorValueBaselineResolver(fallback: troll),
            regeneration: settings
        )
        let holder = ActorValueHolder(
            key: .plugin(name: "skyrim.esm", objectID: 0x0002_3AB7),
            subject: .actor(base: FormID(0x0002_3AB7))
        )
        runtime.damage(.health, by: 50, on: holder)
        for _ in 0 ..< 60 {
            runtime.stepRegeneration(over: [holder]) { _ in
                RegenerationSituation(isInCombat: true, isCasting: false)
            }
        }
        #expect(runtime.current(of: holder).health > 55)
    }
}
