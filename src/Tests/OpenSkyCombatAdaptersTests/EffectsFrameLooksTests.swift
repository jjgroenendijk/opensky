// The effects frame step drops the race looks of actors that left and draws no extra models
// while nothing flies or burns; a spell hit without a session shows nothing.

import Foundation
@testable import OpenSkyCombatAdapters
import OpenSkyFormatsESM
@testable import OpenSkyMagicInterface
import OpenSkySessionTesting
import Testing

@MainActor
struct EffectsFrameLooksTests {
    private let host = CombatHost()
    private static let actor = ReferenceKey.plugin(name: "base.esm", objectID: 0x20)

    private func adapter() -> EffectsWorldAdapter {
        EffectsWorldAdapter(game: host, now: { Date(timeIntervalSince1970: 0) })
    }

    @Test func anActorThatLeftLosesItsRaceLooks() {
        let effects = adapter()
        effects.frameLooks.raceChecked = [Self.actor]
        effects.frameLooks.attachRaceEffects()
        #expect(host.fakeEffects.detachAllCalls == [Self.actor])
        #expect(effects.frameLooks.raceChecked.isEmpty)
    }

    @Test func nothingInFlightDrawsNoExtraModels() {
        #expect(adapter().frameLooks.extraModels().isEmpty)
    }

    @Test func withoutASessionASpellHitShowsNothing() {
        let payload = SpellPayload(
            spell: .plugin(name: "base.esm", objectID: 0x30), sourcePlugin: "base.esm",
            caster: .player, entries: [], isHostile: true, ignoresResistance: false,
            projectile: nil, name: "Flames"
        )
        let event = SpellHitEvent(
            hit: SpellHit(payload: payload, targets: [SpellHitTarget(key: Self.actor)]), links: []
        )
        adapter().handleSpellHit(event)
        #expect(host.fakeEffects.handleSpellHitCalls.isEmpty)
    }
}
