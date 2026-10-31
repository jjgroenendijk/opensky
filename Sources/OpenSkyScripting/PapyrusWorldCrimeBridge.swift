// The crime half of the Papyrus world seam: read, modify, and set crime gold,
// and raise the assault and trespass alarms. Every write is one `CrimeRuntime`
// call. See docs/engine/papyrus-activation.md and docs/engine/crime.md.

import Foundation
import OpenSkyFormatsESM

/// Crime operations a Papyrus native may perform.
@MainActor
public protocol PapyrusWorldCrimeBridge {
    /// Crime gold the player owes `faction`, or nil when this session runs no
    /// crime runtime — a synthetic scene with no FACT index, where answering
    /// zero would read as a player who owes nothing.
    ///
    /// "Get the amount of crime gold on this faction that the player needs to
    /// pay." (<https://ck.uesp.net/wiki/GetCrimeGold_-_Faction>)
    func crimeGold(of faction: ReferenceKey) -> Int?

    /// One half of the player's bounty with `faction`, or nil without a crime
    /// runtime. `GetCrimeGoldViolent` and `GetCrimeGoldNonViolent` read it.
    func crimeGold(of faction: ReferenceKey, violent: Bool) -> Int?

    /// Moves one half of the player's bounty with `faction` by `amount`, clamped at
    /// zero. `abViolent` picks the half (`ModCrimeGold`).
    /// - Returns: the combined bounty afterwards, or nil without a crime runtime.
    @discardableResult
    func modifyCrimeGold(of faction: ReferenceKey, by amount: Int, violent: Bool) -> Int?

    /// Sets one half of the player's bounty outright, leaving the other half and the
    /// crime counts. `SetCrimeGold` sets the non-violent half, `SetCrimeGoldViolent`
    /// the violent one.
    /// - Returns: the combined bounty afterwards, or nil without a crime runtime.
    @discardableResult
    func setCrimeGold(of faction: ReferenceKey, to gold: Int, violent: Bool) -> Int?

    /// Makes `witness` act as if `criminal` assaulted it
    /// (<https://ck.uesp.net/wiki/SendAssaultAlarm_-_Actor>). The bounty goes to the
    /// crime faction of the witness's location.
    /// - Returns: the bounty accrued, or nil without a crime runtime.
    @discardableResult
    func sendAssaultAlarm(witness: ReferenceKey, criminal: ReferenceKey) -> Int?

    /// Makes `witness` act as if it caught `criminal` trespassing
    /// (<https://ck.uesp.net/wiki/SendTrespassAlarm_-_Actor>). No warning comes
    /// first, as the page says.
    /// - Returns: the bounty accrued, or nil without a crime runtime.
    @discardableResult
    func sendTrespassAlarm(witness: ReferenceKey, criminal: ReferenceKey) -> Int?
}
