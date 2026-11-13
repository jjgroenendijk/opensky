// A friend or an ally takes the allowed number of the player's blows before it attacks.

@testable import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyEngineTesting
import OpenSkyFormatsESM
import OpenSkyFormatsTesting
import OpenSkyGameData
import Testing

struct FriendlyFireTests {
    private let guardKey = ReferenceKey.generated(1)

    @Test func aFriendInCombatAttacksOnTheFourthBlow() {
        var fire = CombatLoopRuntime.FriendlyFire()
        let turns = (0 ..< 4).map {
            fire.noteHit(on: guardKey, reaction: .friend, inCombat: true, now: Double($0))
        }
        #expect(turns == [false, false, false, true])
        #expect(fire.count(on: guardKey) == 0)
    }

    @Test func aFriendOutOfCombatAndANeutralAttackAtOnce() {
        var fire = CombatLoopRuntime.FriendlyFire()
        let friend = fire.noteHit(on: guardKey, reaction: .friend, inCombat: false, now: 0)
        let neutral = fire.noteHit(on: guardKey, reaction: .neutral, inCombat: true, now: 0)
        let unknown = fire.noteHit(on: guardKey, reaction: nil, inCombat: true, now: 0)
        #expect(friend && neutral && unknown)
    }

    @Test func quickBlowsCountOnceAndOldBlowsAreForgotten() {
        var fire = CombatLoopRuntime.FriendlyFire()
        _ = fire.noteHit(on: guardKey, reaction: .friend, inCombat: true, now: 0)
        _ = fire.noteHit(on: guardKey, reaction: .friend, inCombat: true, now: 0.2)
        #expect(fire.count(on: guardKey) == 1)
        _ = fire.noteHit(on: guardKey, reaction: .friend, inCombat: true, now: 20)
        #expect(fire.count(on: guardKey) == 1)
    }

    @Test func anAllyInCombatNeverAttacksAndCountsOne() {
        var fire = CombatLoopRuntime.FriendlyFire()
        let inCombat = (0 ..< 10).map {
            fire.noteHit(on: guardKey, reaction: .ally, inCombat: true, now: Double($0))
        }
        #expect(!inCombat.contains(true))
        #expect(fire.count(on: guardKey) == 1)
        let outside = (0 ..< 4).map {
            fire.noteHit(on: guardKey, reaction: .ally, inCombat: false, now: 20 + Double($0))
        }
        #expect(outside == [false, false, false, true])
    }

    @Test func theInstallSettingsReplaceTheDefaults() throws {
        let store = try GameSettingFixture.store(["iFriendHitCombatAllowed": .integer(1)])
        let settings = FriendlyFireSettings.resolve(store: store)
        #expect(settings.friendCombatAllowed == 1)
        #expect(settings.allyNonCombatAllowed == FriendlyFireSettings.vanilla.allyNonCombatAllowed)
    }
}
