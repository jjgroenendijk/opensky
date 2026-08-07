// Live binding from the player's actor values to the vanilla HUD meters
// (issue #194, roadmap item 15.3). The M8 bars stop being a static placeholder
// here.
//
// Engine-side rather than in the AppKit controller, and deliberately so: the
// acceptance gate drives player damage headlessly and watches `HUDMeterValues`
// change through the meter contract, which is only possible if the derivation
// from actor values to meters is testable without a window or an SWF runtime.
// The controller keeps one of these and hands whatever comes out of it to
// `HUDMovieBridge.setMeters(_:runtime:)`; no SWF work was needed.
//
// The change gate is here rather than at the call site because "publish every
// frame they change" is a property of the binding, not of the caller: a meter
// call reaches into the AS2 interpreter and marks the movie dirty, so calling
// it sixty times a second with the same three numbers would re-render a HUD
// that did not move.
//
// Documented in docs/engine/actor-values.md.

import Foundation

nonisolated struct HUDMeterBinding {
    /// What was last handed to the movie. Starts at the value
    /// `HUDMovieBridge.initialize` publishes, so the first real sample only
    /// counts as a change when it actually differs from a full bar.
    private(set) var published: HUDMeterValues

    init(published: HUDMeterValues = .full) {
        self.published = published
    }

    /// The meters for one actor's current values against its maximums.
    ///
    /// A maximum of zero reads as an empty bar rather than a full one: an actor
    /// with no maximum health has no health, and showing that as full would be
    /// the one reading a player must not be given.
    static func meters(current: ActorValues, maximums: ActorValues) -> HUDMeterValues {
        let fractions = current.fractions(of: maximums)
        return HUDMeterValues(
            health: fractions.health,
            magicka: fractions.magicka,
            stamina: fractions.stamina
        )
    }

    /// Records `meters` as the value to publish, returning it when it differs
    /// from what was published last and nil when it does not.
    ///
    /// - Returns: the meters to hand to `HUDMovieBridge.setMeters`, or nil when
    ///   nothing changed this frame.
    mutating func publishing(_ meters: HUDMeterValues) -> HUDMeterValues? {
        guard meters != published else { return nil }
        published = meters
        return meters
    }

    /// Forgets what was published, so the next sample republishes even if it
    /// matches. What a caller does after reloading the movie, which resets the
    /// bars to whatever the SWF authored.
    mutating func invalidate() {
        published = HUDMeterValues(health: .nan, magicka: .nan, stamina: .nan)
    }
}

@MainActor
extension ActorValueRuntime {
    /// `holder`'s current values as HUD meters.
    func hudMeters(for holder: ActorValueHolder) -> HUDMeterValues {
        let baseline = baseline(of: holder)
        return HUDMeterBinding.meters(
            current: current(of: holder),
            maximums: baseline.maximums
        )
    }
}
