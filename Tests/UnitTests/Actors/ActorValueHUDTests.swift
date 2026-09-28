// HUD meter binding tests (issue #194): the acceptance gate's headless half —
// drive player damage and watch `HUDMeterValues` change through the meter
// contract, with no window and no SWF runtime involved.
//
// The other half of the contract, that the movie actually accepts these three
// numbers, is already covered by the M8 HUD tests over the real `hudmenu.swf`;
// nothing about the movie side changed here.

import Foundation
@testable import opensky
import Testing

@MainActor
struct ActorValueHUDBindingTests {
    private func runtime(
        maximums: ActorValues = ActorValues(health: 100, magicka: 80, stamina: 60)
    ) -> ActorValueRuntime {
        ActorValueRuntime(
            store: WorldStateStore(),
            baselines: ActorValueBaselineResolver(
                fallback: ActorValueBaseline(
                    maximums: maximums,
                    regenPercentPerSecond: ActorValues(repeating: 10)
                )
            )
        )
    }

    /// The M8 bars start full and stay full until something touches the player.
    @Test func anUntouchedPlayerReadsFullMeters() {
        #expect(runtime().hudMeters(for: .player) == .full)
    }

    /// Damaging the player moves exactly the meter that was damaged.
    @Test func damagingThePlayerMovesItsMeter() {
        let runtime = runtime()
        runtime.damage(.health, by: 25, on: .player)
        let meters = runtime.hudMeters(for: .player)
        #expect(meters.health == 0.75)
        #expect(meters.magicka == 1)
        #expect(meters.stamina == 1)
    }

    /// The whole gate in one test: damage the player, watch the published
    /// meters change, restore, watch them come back.
    @Test func playerDamagePublishesThroughTheMeterContract() {
        let runtime = runtime()
        var binding = HUDMeterBinding()

        #expect(binding.publishing(runtime.hudMeters(for: .player)) == nil)

        runtime.damage(.health, by: 40, on: .player)
        runtime.damage(.magicka, by: 40, on: .player)
        let hurt = binding.publishing(runtime.hudMeters(for: .player))
        #expect(hurt == HUDMeterValues(health: 0.6, magicka: 0.5, stamina: 1))
        #expect(binding.published == hurt)

        // A frame in which nothing moved publishes nothing, so a static HUD is
        // not re-rendered sixty times a second.
        #expect(binding.publishing(runtime.hudMeters(for: .player)) == nil)

        runtime.restoreAll(on: .player)
        #expect(binding.publishing(runtime.hudMeters(for: .player)) == .full)
    }

    /// Regeneration reaches the meters the same way damage does, one fixed step
    /// at a time.
    @Test func regenerationMovesTheMeters() {
        let runtime = runtime()
        var binding = HUDMeterBinding()
        runtime.damage(.stamina, by: 30, on: .player)
        _ = binding.publishing(runtime.hudMeters(for: .player))
        var accumulator = 0.0
        #expect(runtime.advance(
            delta: 1, accumulator: &accumulator, over: [.player]
        ) == ActorValueRuntime.maximumStepsPerAdvance)
        let published = binding.publishing(runtime.hudMeters(for: .player))
        #expect(published != nil)
        #expect((published?.stamina ?? 0) > 0.5)
    }

    /// A zero delta publishes nothing, which is what a menu-paused frame does.
    @Test func aPausedFramePublishesNothing() {
        let runtime = runtime()
        var binding = HUDMeterBinding()
        runtime.damage(.health, by: 10, on: .player)
        _ = binding.publishing(runtime.hudMeters(for: .player))
        var accumulator = 0.0
        for _ in 0 ..< 100 {
            _ = runtime.advance(delta: 0, accumulator: &accumulator, over: [.player])
            #expect(binding.publishing(runtime.hudMeters(for: .player)) == nil)
        }
    }

    /// An actor with no maximum reads an empty bar rather than a full one.
    @Test func aZeroMaximumReadsEmptyMeters() {
        #expect(runtime(maximums: .zero).hudMeters(for: .player)
            == HUDMeterValues(health: 0, magicka: 0, stamina: 0))
    }

    /// Reloading the movie resets the bars to whatever the SWF authored, so the
    /// binding must republish even when the numbers did not move.
    @Test func invalidatingForcesTheNextPublish() {
        let runtime = runtime()
        var binding = HUDMeterBinding()
        #expect(binding.publishing(runtime.hudMeters(for: .player)) == nil)
        binding.invalidate()
        #expect(binding.publishing(runtime.hudMeters(for: .player)) == .full)
    }
}
