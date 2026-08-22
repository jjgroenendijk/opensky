// The crime half of the Papyrus world seam (issue #504, roadmap item 21.5),
// declared beside the quest, actor and magic halves and refined into
// `PapyrusWorldBridge` the same way.
//
// Five operations, which is the whole crime surface this milestone can back
// with something real: read, modify and set a faction's crime gold, and raise
// the two alarms that make an actor behave as though it had just caught the
// player.
//
// Nothing here writes around `WorldStateStore`. Every mutation is one
// `CrimeRuntime` call, so the journal, the dirty counts and the save see a
// scripted bounty exactly as they see a witnessed theft.
//
// Documented in docs/engine/papyrus-vm.md and docs/engine/crime.md.

import Foundation

/// Crime operations a Papyrus native may perform.
@MainActor
protocol PapyrusWorldCrimeBridge {
    /// Crime gold the player owes `faction`, or nil when this session runs no
    /// crime runtime — a synthetic scene with no FACT index, where answering
    /// zero would read as a player who owes nothing.
    ///
    /// "Get the amount of crime gold on this faction that the player needs to
    /// pay." (<https://ck.uesp.net/wiki/GetCrimeGold_-_Faction>)
    func crimeGold(of faction: ReferenceKey) -> Int?

    /// Moves the player's bounty with `faction` by `amount`, clamped at zero.
    ///
    /// "Modifies the amount of crime gold on this faction." (same wiki,
    /// `ModCrimeGold`) The declared `abViolent` parameter is accepted and
    /// ignored: `CrimeLedgerState` holds one bounty per faction rather than a
    /// violent and a non-violent half, so honouring the flag would need a
    /// split this milestone does not build. Recorded as a limitation in
    /// docs/engine/crime.md rather than answered with a convincing wrong
    /// number.
    ///
    /// - Returns: the bounty afterwards, or nil for a session with no crime
    ///   runtime.
    @discardableResult
    func modifyCrimeGold(of faction: ReferenceKey, by amount: Int) -> Int?

    /// Sets the player's bounty with `faction` outright, leaving the crime
    /// counts alone: paying a fine settles the debt and does not un-commit the
    /// crime.
    ///
    /// - Returns: the bounty afterwards, or nil for a session with no crime
    ///   runtime.
    @discardableResult
    func setCrimeGold(of faction: ReferenceKey, to gold: Int) -> Int?

    /// Makes `witness` behave as though `criminal` had just assaulted it.
    ///
    /// "Have this actor behave as if he was assaulted by the player."
    /// (<https://ck.uesp.net/wiki/SendAssaultAlarm_-_Actor>) The receiver is
    /// the witness and the crime is against it, which is why the bounty lands
    /// with the crime faction of the place the *witness* stands in.
    ///
    /// - Returns: the bounty the alarm accrued, or nil for a session with no
    ///   crime runtime.
    @discardableResult
    func sendAssaultAlarm(witness: ReferenceKey, criminal: ReferenceKey) -> Int?

    /// Makes `witness` behave as though it had caught `criminal` trespassing.
    ///
    /// "Have this actor pretend he caught the specified criminal trespassing."
    /// (<https://ck.uesp.net/wiki/SendTrespassAlarm_-_Actor>) The page also
    /// notes the alarm "is the same as if the player has already committed the
    /// crime of trespassing, and will not result in the 'time to go' dialogue
    /// that precedes the crime", which is why nothing here warns first.
    ///
    /// - Returns: the bounty the alarm accrued, or nil for a session with no
    ///   crime runtime.
    @discardableResult
    func sendTrespassAlarm(witness: ReferenceKey, criminal: ReferenceKey) -> Int?
}

/// Nonisolated hops for the crime operations, mirroring the rest of
/// `PapyrusWorldAccess`: one `MainActor.assumeIsolated` per method, which is an
/// assertion that natives run on the main actor rather than a suppression of
/// the check.
nonisolated extension PapyrusWorldAccess {
    func crimeGold(of faction: ReferenceKey) -> Int? {
        MainActor.assumeIsolated { bridge.crimeGold(of: faction) }
    }

    @discardableResult
    func modifyCrimeGold(of faction: ReferenceKey, by amount: Int) -> Int? {
        MainActor.assumeIsolated { bridge.modifyCrimeGold(of: faction, by: amount) }
    }

    @discardableResult
    func setCrimeGold(of faction: ReferenceKey, to gold: Int) -> Int? {
        MainActor.assumeIsolated { bridge.setCrimeGold(of: faction, to: gold) }
    }

    @discardableResult
    func sendAssaultAlarm(witness: ReferenceKey, criminal: ReferenceKey) -> Int? {
        MainActor.assumeIsolated {
            bridge.sendAssaultAlarm(witness: witness, criminal: criminal)
        }
    }

    @discardableResult
    func sendTrespassAlarm(witness: ReferenceKey, criminal: ReferenceKey) -> Int? {
        MainActor.assumeIsolated {
            bridge.sendTrespassAlarm(witness: witness, criminal: criminal)
        }
    }
}
