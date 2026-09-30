// Ownership resolution: whether an actor owns, or may use, a reference. It
// decides only whether taking a thing would be a crime. First match wins: the
// reference's `XOWN`, then the cell's, then unowned. An `XOWN` link with a FACT
// record is a faction owner, anything else an actor owner. An absent `XRNK`
// reads as rank 0. See docs/engine/crime.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// Resolves `XOWN` links against the load order and answers the ownership
/// question. A value snapshot over the FACT store; answers are pure functions.
nonisolated public struct OwnershipResolver: Sendable {
    /// Rank an owning faction demands when the record authors no `XRNK`.
    ///
    /// Zero, the lowest rank vanilla authors — `ActorFactionMembership.rank` is
    /// signed precisely so a negative rank can mean "a member the rank titles
    /// do not name", and an ordinary rank-0 member of the owning faction is
    /// exactly who a shop's back room is meant to be open to.
    public static let defaultRequiredRank: Int32 = 0

    /// Load-order FACT lookup, which is what distinguishes a faction owner from
    /// an actor owner.
    public let factions: FactionStore
    /// The plugin `XOWN` links are relative to.
    public let pluginName: String

    /// The owner one `XOWN`/`XRNK` pair names. A FACT link is a faction owner;
    /// anything else, even a dangling link, is an actor owner, so a missing plugin
    /// does not make a shop free to loot. Nil only when the link's plugin is not
    /// loaded.
    public func owner(of ownership: RecordOwnership) -> ReferenceOwner? {
        guard let resolved = factions.resolvedID(ownership.owner, fromPlugin: pluginName) else {
            return nil
        }
        let key = ReferenceKey(resolved: resolved)
        guard factions.faction(key: key) != nil else { return .actor(key) }
        return .faction(key, requiredRank: ownership.requiredRank ?? Self.defaultRequiredRank)
    }

    /// The owner in force for a reference, applying the reference-then-cell
    /// precedence.
    public func owner(reference: RecordOwnership?, cell: RecordOwnership?) -> ReferenceOwner? {
        if let reference, let owner = owner(of: reference) {
            return owner
        }
        guard let cell else { return nil }
        return owner(of: cell)
    }

    /// What `actor` may do with a reference owned by `owner`.
    public func verdict(for actor: CrimeActor, owner: ReferenceOwner?) -> OwnershipVerdict {
        actor.verdict(on: owner)
    }

    /// The whole question in one call: the two `XOWN` pairs in, a verdict out.
    public func verdict(
        for actor: CrimeActor,
        reference: RecordOwnership?,
        cell: RecordOwnership?
    ) -> OwnershipVerdict {
        verdict(for: actor, owner: owner(reference: reference, cell: cell))
    }

    public init(factions: FactionStore, pluginName: String) {
        self.factions = factions
        self.pluginName = pluginName
    }
}
