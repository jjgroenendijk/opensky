// The session half of an arrest (issue #505): what `CrimeArrest` cannot do on
// its own because it needs the clock, the player's placement, the streamer and
// the guard state, all of which the session owns.
//
// Declared in the engine so the Papyrus bridge can reach it, and implemented by
// the game controller. Documented in docs/engine/guard-response.md.

import Foundation
import OpenSkyFormats

/// Which way an arrest ends.
nonisolated public enum ArrestOutcome: Equatable, Sendable {
    /// Pay the bounty in gold. `goToJail` moves the player to the faction's
    /// exterior jail marker afterwards, as `PlayerPayCrimeGold`'s parameter of
    /// that name documents: "The player is not actually put in jail, but moved
    /// to the spot where you'd be if you served time and were released from
    /// jail" (<https://ck.uesp.net/wiki/PlayerPayCrimeGold_-_Faction>).
    case pay(removeStolen: Bool, goToJail: Bool)
    /// Serve the sentence.
    case jail
}

/// An arrest outcome run to completion by the session.
@MainActor
public protocol CrimeArrestSession: AnyObject {
    /// Whether the player can pay `faction`'s bounty, or nil for a session with
    /// no crime runtime.
    func canPayCrimeGold(to faction: ReferenceKey) -> Bool?

    /// Runs `outcome` against `faction`'s bounty: the ledger and inventory
    /// through `CrimeArrest`, then the clock and the player's placement.
    ///
    /// - Returns: the settlement or the refusal, or nil for a session with no
    ///   crime runtime.
    func settleArrest(
        with faction: ReferenceKey,
        _ outcome: ArrestOutcome
    ) -> Result<ArrestSettlement, ArrestRefusal>?
}
