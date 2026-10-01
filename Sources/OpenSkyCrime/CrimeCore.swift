// The pure rules of the crime coordinator: readout sentences, the panel's
// faction lists, and what the hostility derivation reads about the player's
// bounties. Values in, values out. See docs/engine/coordinators.md.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState
import simd

/// The three faction lists the panel's popups offer, sorted by name.
nonisolated public struct CrimeFactionOptions: Equatable, Sendable {
    public let all: [FactionOption]
    public let crime: [FactionOption]
    public let vendors: [FactionOption]
}

nonisolated public enum CrimeCore {
    /// How far the player may move from a pursuing guard's last destination
    /// before the guard repaths. Half the confrontation distance, so a guard
    /// never arrives where the player was a whole conversation's reach ago.
    public static let guardRepathDistance: Float = GuardResponseState.confrontDistance / 2

    public static let noFactionTracksCrimeText = "No faction in this load order tracks crime."
    public static let noFactionsText = "This load order carries no factions."

    public static func factionName(_ key: ReferenceKey, in store: FactionStore?) -> String {
        store?.faction(key: key)?.displayName ?? key.description
    }

    public static func factionOption(_ key: ReferenceKey, in store: FactionStore) -> FactionOption {
        FactionOption(key: key, name: factionName(key, in: store))
    }

    /// One outcome as a readout line. A refusal is named, so a zero bounty
    /// never reads as a crime nobody noticed.
    public static func outcomeText(
        _ outcome: CrimeOutcome,
        label: String,
        factionName: String?
    ) -> String {
        let name = factionName ?? "nobody"
        guard let refusal = outcome.refusal else {
            return "\(label): \(outcome.gold) bounty with \(name)."
        }
        return "\(label): no bounty with \(name) — \(refusal.rawValue)."
    }

    /// Sorted once per load order: a vanilla load order carries well over a
    /// thousand factions.
    public static func factionOptions(_ store: FactionStore) -> CrimeFactionOptions {
        let sorted = store.sortedFactions
        func options(_ factions: [ResolvedFaction]) -> [FactionOption] {
            factions
                .map { FactionOption(key: ReferenceKey(resolved: $0.id), name: $0.displayName) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        }
        return CrimeFactionOptions(
            all: options(sorted),
            crime: options(sorted.filter(\.faction.tracksCrime)),
            vendors: options(sorted.filter(\.faction.isVendor))
        )
    }

    public static func bountyReadouts(
        _ ledger: CrimeLedgerState,
        factions store: FactionStore
    ) -> [BountyReadout] {
        ledger.entries.filter { !$0.isEmpty }.map { entry in
            BountyReadout(
                faction: factionOption(entry.faction, in: store),
                nonViolentGold: entry.nonViolentGold,
                violentGold: entry.violentGold,
                counts: entry.counts,
                response: CrimeResponsePolicy.response(
                    bounty: entry.gold,
                    values: store.faction(key: entry.faction)?.faction.crimeValues
                )
            )
        }
    }

    /// The owner a verdict was reached against, by name.
    public static func ownerName(_ owner: ReferenceOwner?, in store: FactionStore) -> String? {
        switch owner {
        case nil:
            nil
        case let .actor(base):
            "NPC_ \(base)"
        case let .faction(key, requiredRank):
            "\(factionName(key, in: store)) (rank \(requiredRank) or higher)"
        }
    }

    /// Every faction the player owes, with its crime values, and the factions
    /// the player resisted.
    public static func guardHostility(
        ledger: CrimeLedgerState,
        factions store: FactionStore,
        resisted: Set<ReferenceKey>
    ) -> GuardCrimeHostility {
        var bounties: [ReferenceKey: Int32] = [:]
        var values: [ReferenceKey: Faction.CrimeValues] = [:]
        for entry in ledger.entries where entry.gold > 0 {
            bounties[entry.faction] = entry.gold
            values[entry.faction] = store.faction(key: entry.faction)?.faction.crimeValues
        }
        return GuardCrimeHostility(
            guardFaction: store.guardFactionKey,
            bounties: bounties,
            crimeValues: values,
            resisted: resisted
        )
    }

    public static func guardKey(of action: GuardAction) -> ReferenceKey {
        switch action {
        case let .pursue(guardKey, _), let .confront(guardKey, _, _): guardKey
        }
    }

    /// A pursuing guard repaths only once the player has moved away from where
    /// it was last sent.
    public static func needsRepath(lastTarget: SIMD3<Float>?, player: SIMD3<Float>) -> Bool {
        guard let lastTarget else { return true }
        return simd_distance(lastTarget, player) >= guardRepathDistance
    }

    public static func settlementText(
        _ settlement: ArrestSettlement,
        factionName: String,
        moved: Bool
    ) -> String {
        let seized = settlement.confiscated.reduce(0) { $0 + Int($1.count) }
        let how = settlement.sentenceDays > 0
            ? "Served \(settlement.sentenceDays) days"
            : "Paid \(settlement.goldPaid) gold"
        let placement = switch (settlement.releaseMarker, moved) {
        case (nil, _): ""
        case (_, true): ", moved to the jail marker"
        case (_, false): ", jail marker not resident"
        }
        return "\(how) to \(factionName) for a \(settlement.bounty) bounty; "
            + "\(seized) stolen items seized\(placement)."
    }
}
