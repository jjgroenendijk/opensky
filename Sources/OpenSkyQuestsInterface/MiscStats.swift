// The misc stats the journal's Stats page lists and `Game.QueryStat` reads. The
// names are the Creation Kit's list; the six categories follow the list order.
// See docs/engine/journal.md, Stats page.

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// The journal's six stat groups, in the movie's `CategoryList` order.
nonisolated public enum MiscStatCategory: Int, CaseIterable, Sendable {
    case general = 0, quest, combat, magic, crafting, crime
}

nonisolated public struct MiscStat: Equatable, Sendable {
    public let name: String
    public let category: MiscStatCategory
    /// False for the per-hold bounties and the "Favorite" text stats.
    public let isListed: Bool
}

nonisolated public enum MiscStats {
    /// <https://ck.uesp.net/wiki/QueryStat_-_Game>, in its order.
    public static let catalog: [MiscStat] = {
        let groups: [(MiscStatCategory, [String])] = [
            (.general, general), (.quest, quest), (.combat, combat),
            (.magic, magic), (.crafting, crafting), (.crime, crime)
        ]
        let shown = groups.flatMap { category, names in
            names.map {
                MiscStat(name: $0, category: category, isListed: !$0.hasPrefix("Favorite"))
            }
        }
        return shown + holdBounties.map { MiscStat(name: $0, category: .crime, isListed: false) }
    }()

    private static let byName: [String: MiscStat] = Dictionary(
        catalog.map { ($0.name.lowercased(), $0) }
    ) { first, _ in first }

    /// Case-insensitive, as Papyrus strings compare.
    public static func stat(named name: String) -> MiscStat? {
        byName[name.lowercased()]
    }

    /// `Game.QueryStat`'s name for each quest type's completion count.
    public static let questsCompleted = "Quests Completed"

    private static let general = [
        "Locations Discovered", "Dungeons Cleared", "Days Passed", "Hours Slept", "Hours Waiting",
        "Standing Stones Found", "Gold Found", "Most Gold Carried", "Chests Looted",
        "Skill Increases", "Skill Books Read", "Food Eaten", "Training Sessions", "Books Read",
        "Horses Owned", "Houses Owned", "Stores Invested In", "Barters", "Persuasions", "Bribes",
        "Intimidations", "Diseases Contracted", "Days as a Vampire", "Days as a Werewolf",
        "Necks Bitten", "Vampirism Cures", "Werewolf Transformations", "Mauls"
    ]
    private static let quest = [
        "Quests Completed", "Misc Objectives Completed", "Main Quests Completed",
        "Side Quests Completed", "The Companions Quests Completed",
        "College of Winterhold Quests Completed", "Thieves' Guild Quests Completed",
        "The Dark Brotherhood Quests Completed", "Civil War Quests Completed",
        "Daedric Quests Completed", "Dawnguard Quests Completed", "Dragonborn Quests Completed",
        "Questlines Completed"
    ]
    private static let combat = [
        "People Killed", "Animals Killed", "Creatures Killed", "Undead Killed", "Daedra Killed",
        "Automatons Killed", "Favorite Weapon", "Critical Strikes", "Sneak Attacks", "Backstabs",
        "Weapons Disarmed", "Brawls Won", "Bunnies Slaughtered"
    ]
    private static let magic = [
        "Spells Learned", "Favorite Spell", "Favorite School", "Dragon Souls Collected",
        "Words Of Power Learned", "Words Of Power Unlocked", "Shouts Learned", "Shouts Unlocked",
        "Shouts Mastered", "Times Shouted", "Favorite Shout", "Soul Gems Used", "Souls Trapped"
    ]
    private static let crafting = [
        "Magic Items Made", "Weapons Improved", "Weapons Made", "Armor Improved", "Armor Made",
        "Potions Mixed", "Potions Used", "Poisons Mixed", "Poisons Used", "Ingredients Harvested",
        "Ingredients Eaten", "Nirnroots Found", "Wings Plucked"
    ]
    private static let crime = [
        "Total Lifetime Bounty", "Largest Bounty", "Locks Picked", "Pockets Picked",
        "Items Pickpocketed", "Times Jailed", "Days Jailed", "Fines Paid", "Jail Escapes",
        "Items Stolen", "Assaults", "Murders", "Horses Stolen", "Trespasses"
    ]
    private static let holdBounties = [
        "Eastmarch Bounty", "Falkreath Bounty", "Haafingar Bounty", "Hjaalmarch Bounty",
        "The Pale Bounty", "The Reach Bounty", "The Rift Bounty", "Tribal Orcs Bounty",
        "Whiterun Bounty", "Winterhold Bounty"
    ]
}

/// The counted stats, keyed on the player. A stat never counted reads 0.
nonisolated public struct MiscStatsState: WorldStateComponent, Sendable {
    /// Keyed by the catalog's spelling.
    public var values: [String: Int32]

    public static var componentKind: WorldStateComponentKind {
        .miscStats
    }

    public init(values: [String: Int32] = [:]) {
        self.values = values
    }

    public func value(_ name: String) -> Int32 {
        MiscStats.stat(named: name).flatMap { values[$0.name] } ?? 0
    }

    /// False for a name outside the catalog, which the game ignores too.
    @discardableResult
    public mutating func increment(_ name: String, by amount: Int32 = 1) -> Bool {
        guard let stat = MiscStats.stat(named: name) else { return false }
        let (sum, overflow) = values[stat.name, default: 0].addingReportingOverflow(amount)
        values[stat.name] = overflow ? (amount > 0 ? .max : .min) : sum
        return true
    }
}

extension WorldStateStore {
    public var miscStats: MiscStatsState {
        component(MiscStatsState.self, for: .player) ?? MiscStatsState()
    }

    /// False for a name outside the catalog.
    @discardableResult
    public func incrementMiscStat(_ name: String, by amount: Int32 = 1) -> Bool {
        var stats = miscStats
        guard stats.increment(name, by: amount) else { return false }
        set(stats, for: .player)
        return true
    }
}

/// Whether the player tracks a quest: its targets show on the compass and the map,
/// and the journal marks it active. Keyed on the QUST record. No component means
/// the quest was never shown, so its first objective tracks it.
nonisolated public struct QuestTrackingState: WorldStateComponent, Sendable {
    public var isTracked: Bool

    public static var componentKind: WorldStateComponentKind {
        .questTracking
    }

    public init(isTracked: Bool) {
        self.isTracked = isTracked
    }
}

nonisolated extension WorldStateComponentKind {
    public static let miscStats = Self(rawValue: "miscStats", order: 33, affectsCellBuild: false)
    public static let questTracking = Self(
        rawValue: "questTracking", order: 34, affectsCellBuild: false
    )
}
