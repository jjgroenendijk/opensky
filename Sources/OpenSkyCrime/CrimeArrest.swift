// How an arrest ends (issue #505, roadmap item 21.6): paying the fine, going
// to jail, and what both do to the ledger and the player's inventory.
//
// ## Sources
//
// UESP's Crime page (<https://en.uesp.net/wiki/Skyrim:Crime>) is the
// behavioural source for both outcomes: "If you choose to pay off your bounty,
// all stolen items in your possession will be seized and put into the jail's
// evidence chest", "If you cannot (or choose not to) pay your bounty, you will
// be incarcerated in the nearest jail", "All items that are confiscated as a
// result of your arrest or jail time will be stored in an evidence chest in the
// jail of the hold", and "The maximum sentence is seven days ... You will serve
// the maximum sentence for any bounty 700 or higher". A day per hundred gold,
// at least one and at most seven, is the reading of that last line this engine
// takes; nothing open states the rounding.
//
// The Creation Kit signatures are `Faction.PlayerPayCrimeGold(bool
// abRemoveStolenItems = True, bool abGoToJail = True)` and
// `Faction.SendPlayerToJail(bool abRemoveInventory = True, bool abRealJail =
// True)` (<https://ck.uesp.net/wiki/PlayerPayCrimeGold_-_Faction>,
// <https://ck.uesp.net/wiki/SendPlayerToJail_-_Faction>). The evidence chest is
// the faction's `STOL` link and the release point its `JAIL` link — the
// "Stolen Goods Container" and "Exterior Jail Marker" of the Creation Kit's
// Faction page.
//
// ## What v1 leaves out
//
// Serving a sentence here is instantaneous bookkeeping: the bounty clears,
// stolen goods go to the evidence chest, and the session advances the clock by
// the sentence and moves the player to the release marker when it can. The
// jail cell itself, the belongings chest (`PLCN`) the player's gear waits in,
// the jail outfit, escaping, and the skill-progress loss UESP describes are
// not modelled; the gear round trip nets out to nothing once the sentence is
// served, so skipping it changes no end state. Recorded in
// docs/engine/guard-response.md.
//
// Documented in docs/engine/guard-response.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// The two ways an arrest ends, over the crime ledger and the inventory.
@MainActor
public struct CrimeArrest {
    /// Gold of bounty per day of sentence, and the longest sentence, from
    /// UESP's "maximum sentence is seven days ... for any bounty 700 or higher".
    public static let goldPerSentenceDay: Int32 = 100
    public static let maximumSentenceDays = 7

    public let crime: CrimeRuntime
    public let inventory: any InventoryAccess

    /// Days served for `bounty`: one per hundred gold, at least one, at most
    /// seven.
    public static func sentenceDays(bounty: Int32) -> Int {
        guard bounty > 0 else { return 0 }
        return min(maximumSentenceDays, max(1, Int(bounty / goldPerSentenceDay)))
    }

    /// `Faction.CanPayCrimeGold`: whether the player carries enough gold to
    /// clear the bounty. False when there is no bounty, because there is
    /// nothing to pay.
    public func canPay(_ faction: ReferenceKey) -> Bool {
        let owed = crime.crimeGold(of: faction)
        return owed > 0 && inventory.goldCount(of: .player) >= owed
    }

    /// The faction's evidence chest (`STOL`) as a runtime identity.
    public func evidenceChest(of faction: ReferenceKey) -> ReferenceKey? {
        guard let resolved = crime.factions.faction(key: faction) else { return nil }
        return crime.factions.linkKey(resolved.faction.evidenceChest, of: resolved)
    }

    /// The faction's exterior jail marker (`JAIL`) as a runtime identity.
    public func releaseMarker(of faction: ReferenceKey) -> ReferenceKey? {
        guard let resolved = crime.factions.faction(key: faction) else { return nil }
        return crime.factions.linkKey(resolved.faction.exteriorJailMarker, of: resolved)
    }

    /// `Faction.PlayerPayCrimeGold`: takes the bounty in gold, clears it, and
    /// seizes stolen goods into `evidence` when `removeStolen` is set.
    ///
    /// - Parameter evidence: the evidence chest's inventory holder, which the
    ///   session resolves because only it knows whether the chest is resident.
    ///   Nil keeps the stolen goods with the player — a faction with no `STOL`
    ///   has nowhere to put them, and deleting items is not what seizing means.
    /// - Throws: `ArrestRefusal`, writing nothing.
    @discardableResult
    public func pay(
        _ faction: ReferenceKey,
        removeStolen: Bool = true,
        goToJail: Bool = false,
        evidence: InventoryHolder?
    ) throws(ArrestRefusal) -> ArrestSettlement {
        let owed = crime.crimeGold(of: faction)
        guard owed > 0 else { throw .noBounty }
        let gold = inventory.goldCount(of: .player)
        guard gold >= owed else { throw .cannotAfford(owed: owed, gold: gold) }
        // Checked above, so the removal cannot fail; `try?` keeps a surprise
        // from crashing the session rather than hiding a real error path.
        _ = try? inventory.remove(inventory.goldFormID, count: owed, from: .player)
        let confiscated = removeStolen ? confiscate(into: evidence) : []
        crime.clearCrimeGold(of: faction)
        return ArrestSettlement(
            faction: faction,
            bounty: owed,
            goldPaid: owed,
            confiscated: confiscated,
            evidenceChest: confiscated.isEmpty ? nil : evidence?.key,
            sentenceDays: 0,
            releaseMarker: goToJail ? releaseMarker(of: faction) : nil
        )
    }

    /// `Faction.SendPlayerToJail`: seizes stolen goods, clears the bounty, and
    /// reports the sentence for the session to serve.
    ///
    /// - Throws: `ArrestRefusal.noBounty`, writing nothing.
    @discardableResult
    public func jail(
        _ faction: ReferenceKey,
        evidence: InventoryHolder?
    ) throws(ArrestRefusal) -> ArrestSettlement {
        let owed = crime.crimeGold(of: faction)
        guard owed > 0 else { throw .noBounty }
        let confiscated = confiscate(into: evidence)
        crime.clearCrimeGold(of: faction)
        return ArrestSettlement(
            faction: faction,
            bounty: owed,
            goldPaid: 0,
            confiscated: confiscated,
            evidenceChest: confiscated.isEmpty ? nil : evidence?.key,
            sentenceDays: Self.sentenceDays(bounty: owed),
            releaseMarker: releaseMarker(of: faction)
        )
    }

    /// The evidence chest's holder when the chest is not resident: its key and
    /// no plugin baseline. Stated limitation — a chest first touched this way
    /// stops reading its `CNTO` list. Harmless on vanilla data: every `STOL`
    /// in `Skyrim.esm` places `EvidenceChestStolenGoods` or
    /// `EvidenceChestPlayerInventory`, neither of which authors a `CNTO`.
    /// Recorded in docs/engine/guard-response.md.
    public func unresidentEvidence(of faction: ReferenceKey) -> InventoryHolder? {
        evidenceChest(of: faction).map { InventoryHolder(key: $0, owner: .generated) }
    }

    private func confiscate(into evidence: InventoryHolder?) -> [InventoryStack] {
        guard let evidence else { return [] }
        return (try? inventory.confiscateStolen(from: .player, to: evidence)) ?? []
    }

    public init(crime: CrimeRuntime, inventory: any InventoryAccess) {
        self.crime = crime
        self.inventory = inventory
    }
}
