// Binds the player's actor values to the vanilla HUD meters
// (docs/engine/actor-value-store.md). Engine-side so tests can drive it
// headless. It publishes only on change, because each call dirties the movie.

import Foundation
import OpenSkyActorsInterface
import OpenSkyGameData

nonisolated public struct HUDMeterBinding: Sendable {
    /// What was last handed to the movie. Starts at the value
    /// `HUDMovieBridge.initialize` publishes, so the first real sample only
    /// counts as a change when it actually differs from a full bar.
    public private(set) var published: HUDMeterValues

    public init(published: HUDMeterValues = .full) {
        self.published = published
    }

    /// The meters for one actor's current values against its maximums.
    ///
    /// A maximum of zero reads as an empty bar rather than a full one: an actor
    /// with no maximum health has no health, and showing that as full would be
    /// the one reading a player must not be given.
    public static func meters(current: ActorValues, maximums: ActorValues) -> HUDMeterValues {
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
    public mutating func publishing(_ meters: HUDMeterValues) -> HUDMeterValues? {
        guard meters != published else { return nil }
        published = meters
        return meters
    }

    /// Forgets what was published, so the next sample republishes even if it
    /// matches. What a caller does after reloading the movie, which resets the
    /// bars to whatever the SWF authored.
    public mutating func invalidate() {
        published = HUDMeterValues(health: .nan, magicka: .nan, stamina: .nan)
    }
}

@MainActor
extension ActorValueAccess {
    /// `holder`'s current values as HUD meters.
    public func hudMeters(for holder: ActorValueHolder) -> HUDMeterValues {
        // The effective maximums, not the derived ones: since item 20.3 a base
        // write or a fortify moves the ceiling the bar is drawn against, and a
        // bar drawn against the derived number would read past full.
        HUDMeterBinding.meters(
            current: current(of: holder),
            maximums: maximums(of: holder)
        )
    }
}
