// The seam other features report crimes and read bounty through. `CrimeReporter` in
// OpenSkyCrime conforms, and the composition root hands it over as this protocol.

import OpenSkyFormatsESM

/// Judges ownership, reports crimes, and reads and writes the player's bounty.
@MainActor
public protocol CrimeReporting: AnyObject {
    /// The session the reporter asks about owners, cells, and actors.
    var world: (any CrimeWorld)? { get }

    /// Whether `actor` taking `reference` would be theft, and from whom.
    func verdict(on reference: ReferenceKey, by actor: ReferenceKey) -> OwnershipVerdict

    /// Reports a theft, run past the witnesses.
    @discardableResult
    func reportTheft(
        of item: FormID,
        count: Int32,
        from reference: ReferenceKey,
        owner: ReferenceOwner?,
        by actor: ReferenceKey
    ) -> CrimeOutcome

    /// Reports `event` as it stands, with no witness check.
    @discardableResult
    func report(_ event: CrimeEvent) -> CrimeOutcome

    /// The player's bounty with `faction`.
    func crimeGold(of faction: ReferenceKey) -> Int32

    /// The player's violent or non-violent bounty with `faction`.
    func crimeGold(of faction: ReferenceKey, violent: Bool) -> Int32

    /// Adds `delta` to the player's bounty with `faction`, and returns the new value.
    @discardableResult
    func modifyCrimeGold(by delta: Int32, violent: Bool, of faction: ReferenceKey) -> Int32

    /// Sets the player's bounty with `faction`, and returns the new value.
    @discardableResult
    func setCrimeGold(_ gold: Int32, violent: Bool, of faction: ReferenceKey) -> Int32
}

extension CrimeReporting {
    /// Whether the player taking `reference` would be theft.
    public func verdict(on reference: ReferenceKey) -> OwnershipVerdict {
        verdict(on: reference, by: .player)
    }

    /// Reports a theft by the player.
    @discardableResult
    public func reportTheft(
        of item: FormID,
        count: Int32,
        from reference: ReferenceKey,
        owner: ReferenceOwner?
    ) -> CrimeOutcome {
        reportTheft(of: item, count: count, from: reference, owner: owner, by: .player)
    }
}
