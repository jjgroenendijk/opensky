// An actor that sees a friend die turns on the killer and says its line.
// docs/engine/combat-detection-dialogue.md#detectfrienddie.

import Foundation
import OpenSkyActorsInterface
import OpenSkyCombatInterface
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics
import OpenSkySessionTesting
@testable import OpenSkyStoryAdapters
import Testing

@MainActor
struct StoryFriendDeathTests {
    private let host = StoryHost()
    private let loop = FakeCombatLoopRuntimePort()
    private var talk: StoryAmbientTalkAdapter {
        StoryWorldAdapter(
            game: host, stage: nil, now: { Date(timeIntervalSinceReferenceDate: 0) }
        ).ambientTalk
    }

    init() {
        host.fakeDialogue.speechTimersValue = SpeechTimerSettings()
        host.fakeScenes.catalogValue = .empty
        host.fakeStreamer.dynamicBodiesValue = DynamicBodyWorld()
    }

    private static let victim = ReferenceKey.plugin(name: "base.esm", objectID: 0x30)
    private static let friend = ReferenceKey.plugin(name: "base.esm", objectID: 0x31)
    private static let far = ReferenceKey.plugin(name: "base.esm", objectID: 0x32)

    private func actors(victimIsDead: Bool) -> [CombatActorObservation] {
        [
            CombatActorObservation(key: Self.victim, feet: .zero, isDead: victimIsDead),
            CombatActorObservation(key: Self.friend, feet: SIMD3(500, 0, 0)),
            CombatActorObservation(key: Self.far, feet: SIMD3(5000, 0, 0))
        ]
    }

    @Test func theRuleFollowsThePage() {
        var witness = FriendDeathWitness()
        #expect(!FriendDeathRule.turnsOnKiller(witness))
        witness.isFriendOfVictim = true
        #expect(FriendDeathRule.turnsOnKiller(witness))
        witness.isFriendOfKiller = true
        #expect(!FriendDeathRule.turnsOnKiller(witness))
        witness.isInCrimeFaction = true
        #expect(FriendDeathRule.turnsOnKiller(witness))
        witness.detectsKiller = true
        #expect(!FriendDeathRule.turnsOnKiller(witness), "a guard takes the crime path")
        var enemy = FriendDeathWitness()
        enemy.isHostileToKiller = true
        #expect(FriendDeathRule.turnsOnKiller(enemy))
    }

    @Test func aNearFriendOfTheVictimFightsTheKillerAndSpeaks() {
        host.fakeCombat.loop = loop
        loop.startCombatResult = true
        host.fakeFactions.reactionResult = .friend
        host.fakeFactions.hostilityResult = .hostile
        host.fakeDialogue.friendDeathLineResult = FormID(0x900)
        let talk = talk
        // The first pass only learns who is dead already.
        talk.witnessDeaths(among: actors(victimIsDead: false)) { _ in .player }
        #expect(loop.startCombatCalls.isEmpty)
        talk.witnessDeaths(among: actors(victimIsDead: true)) { _ in .player }
        #expect(loop.startCombatCalls.map(\.actor) == [Self.friend])
        #expect(host.fakeDialogue.friendDeathLineCalls == [Self.friend])
        // A body that is known has no new witnesses, and a death with no killer has none.
        talk.witnessDeaths(among: actors(victimIsDead: true)) { _ in .player }
        #expect(loop.startCombatCalls.count == 1)
    }

    @Test func aDeathByAnotherActorReadsTheReactionToThatActor() {
        host.fakeCombat.loop = loop
        host.fakeFactions.reactionResult = .enemy
        let talk = talk
        talk.witnessDeaths(among: actors(victimIsDead: false)) { _ in nil }
        talk.witnessDeaths(among: actors(victimIsDead: true)) { _ in Self.far }
        #expect(loop.startCombatCalls.map(\.actor) == [Self.friend])
        #expect(host.fakeDialogue.friendDeathLineCalls.isEmpty)
    }
}
