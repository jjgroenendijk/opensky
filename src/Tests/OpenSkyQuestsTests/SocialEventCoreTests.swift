// The NPC social pass: random conversations on a timer, hellos in passing, and
// found bodies, each once and only for free actors whose package allows it.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyQuests
import Testing

struct SocialEventCoreTests {
    private let first = ReferenceKey.plugin(name: "test.esm", objectID: 0x100)
    private let second = ReferenceKey.plugin(name: "test.esm", objectID: 0x101)
    /// Every attempt passes the chance roll, and the timer is one second.
    private let settings = SocialSettings(
        radius: 500, interiorRadius: 500, chance: 100, interiorChance: 100,
        timerMin: 1, timerMax: 1, triggerDistance: 200, sameActorSeconds: 120
    )

    private func actor(
        _ key: ReferenceKey, x: Float, flags: UInt16? = 0x02,
        isDead: Bool = false, isInScene: Bool = false
    ) -> SocialActor {
        SocialActor(
            key: key, feet: SIMD3(x, 0, 0), interruptFlags: flags,
            isDead: isDead, isInScene: isInScene
        )
    }

    private func pass(
        _ actors: [SocialActor], now: Double, state: inout SocialState,
        inConversation: Bool = false, canSee: Bool = true
    ) -> [String] {
        let frame = SocialFrame(
            actors: actors, now: now, isInterior: false, playerInConversation: inConversation
        )
        return SocialEventCore.events(frame, settings: settings, state: &state) { _, _ in canSee }
            .map(\.event.description)
    }

    @Test func twoNearActorsTalkWhenTheTimerRunsOut() {
        var state = SocialState()
        let actors = [actor(first, x: 0), actor(second, x: 100)]
        #expect(pass(actors, now: 0, state: &state).isEmpty)
        #expect(pass(actors, now: 2, state: &state) == ["ADIA"])
        #expect(pass(actors, now: 4, state: &state).isEmpty, "same pair within 120 s")
    }

    @Test func noConversationOutsideTheTriggerDistanceOrWithoutTheFlag() {
        var state = SocialState()
        let far = [actor(first, x: 0), actor(second, x: 300)]
        _ = pass(far, now: 0, state: &state)
        #expect(pass(far, now: 2, state: &state).isEmpty)
        var flagless = SocialState()
        let quiet = [actor(first, x: 0, flags: 0), actor(second, x: 100, flags: 0)]
        _ = pass(quiet, now: 0, state: &flagless)
        #expect(pass(quiet, now: 2, state: &flagless).isEmpty)
    }

    @Test func aSceneOrThePlayersConversationStopsChatter() {
        var state = SocialState()
        let busy = [actor(first, x: 0), actor(second, x: 100, isInScene: true)]
        _ = pass(busy, now: 0, state: &state)
        #expect(pass(busy, now: 2, state: &state).isEmpty)
        let free = [actor(first, x: 0), actor(second, x: 100)]
        #expect(pass(free, now: 3, state: &state, inConversation: true).isEmpty)
    }

    @Test func aWalkerSaysHelloToAStandingActorOnce() {
        var state = SocialState()
        _ = pass([actor(first, x: -50), actor(second, x: 100)], now: 0, state: &state)
        let events = pass([actor(first, x: 50), actor(second, x: 100)], now: 0.5, state: &state)
        #expect(events == ["AHEL"])
        let again = pass([actor(first, x: 60), actor(second, x: 100)], now: 0.8, state: &state)
        #expect(!again.contains("AHEL"))
    }

    @Test func anActorThatGreetsCorpsesFindsABodyOnce() {
        var state = SocialState()
        let actors = [actor(first, x: 0, flags: 0x08), actor(second, x: 300, isDead: true)]
        #expect(pass(actors, now: 0, state: &state, canSee: false).isEmpty)
        #expect(pass(actors, now: 1, state: &state) == ["DEAD"])
        #expect(pass(actors, now: 2, state: &state).isEmpty)
    }

    @Test func settingsReadTheSocialGameSettings() {
        let defaults = SocialSettings.documentedDefaults
        #expect(defaults.radius == 2000)
        #expect(defaults.sameActorSeconds == 120)
    }
}
