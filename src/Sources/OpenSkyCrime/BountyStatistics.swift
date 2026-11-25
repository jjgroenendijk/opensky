// The game's own bounty statistics, kept on its "bounty changed" event. See
// docs/engine/crime-reports.md, Statistics.

import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData

/// Turns one change of the player's bounty with one faction into stat commands.
nonisolated enum BountyStatistics {
    /// The hidden per-hold statistic each vanilla hold faction keeps.
    static let holdStatistics: [String: String] = [
        "CrimeFactionEastmarch": "Eastmarch Bounty",
        "CrimeFactionFalkreath": "Falkreath Bounty",
        "CrimeFactionHaafingar": "Haafingar Bounty",
        "CrimeFactionHjaalmarch": "Hjaalmarch Bounty",
        "CrimeFactionPale": "The Pale Bounty",
        "CrimeFactionReach": "The Reach Bounty",
        "CrimeFactionRift": "The Rift Bounty",
        "CrimeFactionOrcs": "Tribal Orcs Bounty",
        "CrimeFactionWhiterun": "Whiterun Bounty",
        "CrimeFactionWinterhold": "Winterhold Bounty"
    ]

    /// The commands for a bounty that went from `old` to `new`. A faction that does
    /// not track crime, or carries the hidden flag, changes nothing.
    static func commands(
        editorID: String?, counts: Bool, old: Int32, new: Int32
    ) -> [CrimeCommand] {
        guard counts, old != new else { return [] }
        var commands: [CrimeCommand] = []
        if let editorID, let statistic = holdStatistics[editorID] {
            commands.append(.setStat(statistic, to: new))
        }
        if new > old {
            commands.append(.raiseStat("Largest Bounty", to: new))
            commands.append(.incrementStat("Total Lifetime Bounty", by: new - old))
        }
        return commands
    }
}

extension CrimeCoordinator {
    /// Compares the player's bounties with the last tick's and counts each change,
    /// so a script, a fine, and a crime all count alike. The first look only records.
    func countBountyChanges() {
        BountyCount(owner: self).countBountyChanges()
    }
}

extension CrimeCoordinator {
    /// Counts the bounty changes for the statistics.
    struct BountyCount {
        let owner: CrimeCoordinator

        func countBountyChanges() {
            guard let runtime = owner.reporter?.runtime else { return }
            let bounties = Dictionary(
                runtime.ledger().entries.map { ($0.faction, $0.gold) }
            ) { first, _ in first }
            defer { owner.lastBounties = bounties }
            guard let previous = owner.lastBounties else { return }
            for faction in Set(bounties.keys).union(previous.keys).sorted() {
                let record = runtime.factions.faction(key: faction)?.faction
                owner.pendingCommands += BountyStatistics.commands(
                    editorID: record?.editorID,
                    counts: record.map { $0.tracksCrime && !$0.flags.contains(.hiddenFromNPC) }
                        ?? false,
                    old: previous[faction] ?? 0, new: bounties[faction] ?? 0
                )
            }
        }
    }
}
