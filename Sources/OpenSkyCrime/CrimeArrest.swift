// How an arrest ends: pay the fine or go to jail, per UESP
// (<https://en.uesp.net/wiki/Skyrim:Crime>). The sentence is `CrimeSettings`:
// one day per `iCrimeDaysInPrisonMod` gold, at most `iCrimeMaxNumberofDaysinJail`.
// The evidence chest is the faction's `STOL`, the release point its `JAIL`.
// See docs/engine/jail.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

/// The two ways an arrest ends, over the crime ledger and the inventory.
@MainActor
public struct CrimeArrest {
    public let crime: CrimeRuntime
    public let inventory: any InventoryAccess

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

    /// The faction's chest for the player's belongings (`PLCN`) as a runtime identity.
    public func belongingsChest(of faction: ReferenceKey) -> ReferenceKey? {
        guard let resolved = crime.factions.faction(key: faction) else { return nil }
        return crime.factions.linkKey(resolved.faction.playerInventoryContainer, of: resolved)
    }

    /// The faction's jail outfit (`JOUT`), in the load-order space.
    public func jailOutfit(of faction: ReferenceKey) -> FormID? {
        guard let resolved = crime.factions.faction(key: faction) else { return nil }
        return crime.factions.linkFormID(resolved.faction.jailOutfit, of: resolved)
    }

    /// `Faction.PlayerPayCrimeGold`: takes the bounty in gold, clears it, and seizes
    /// stolen goods into `evidence` when `removeStolen` is set. A nil `evidence`
    /// (no `STOL`) keeps them with the player. Throws `ArrestRefusal`, writing nothing.
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
            sentenceDays: crime.settings.sentenceDays(bounty: owed),
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
