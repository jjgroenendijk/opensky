// The misc stats the journal's Stats page lists and `Game.QueryStat` reads. The
// names are the Creation Kit's list; the six categories follow the list order.
// See docs/engine/journal.md, Stats page.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyWorldState

/// The journal's six stat groups, in the movie's `CategoryList` order.
nonisolated public enum MiscStatCategory: Int, CaseIterable, Sendable {
    case general = 0, quest, combat, magic, crafting, crime
}

nonisolated public struct MiscStat: Equatable, Sendable {
    public let name: String
    public let category: MiscStatCategory
    /// False for the per-hold bounties.
    public let isListed: Bool

    /// A "Favorite" stat shows a name, not a count, and `Game.QueryStat` reads it as 0.
    public var isText: Bool {
        name.hasPrefix("Favorite")
    }
}

nonisolated public enum MiscStats {
    /// <https://ck.uesp.net/wiki/QueryStat_-_Game>, in its order.
    public static let catalog: [MiscStat] = {
        let groups: [(MiscStatCategory, [String])] = [
            (.general, general), (.quest, quest), (.combat, combat),
            (.magic, magic), (.crafting, crafting), (.crime, crime)
        ]
        let shown = groups.flatMap { category, names in
            names.map { MiscStat(name: $0, category: category, isListed: true) }
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

    /// The stats one day-passed event raises. The two flags are the globals the
    /// `PIVV` and `PIWV` default objects name (docs/engine/statistics.md, Days).
    public static func dayPassed(isVampire: Bool, isWerewolf: Bool) -> [String] {
        ["Days Passed"] + (isVampire ? ["Days as a Vampire"] : [])
            + (isWerewolf ? ["Days as a Werewolf"] : [])
    }

    /// The shout stats `Game.UnlockWord` raises for `word`. `slots` holds each shout's
    /// word slots, nil for a slot without both a word and a spell (docs/engine/statistics.md).
    public static func wordUnlocked(
        _ word: ReferenceKey, slots: [ReferenceKey: [ReferenceKey?]]
    ) -> [String] {
        var stats: [String] = []
        for words in slots.values where words.contains(word) {
            if words.first == word {
                stats.append("Shouts Unlocked")
            }
            if words.last(where: { $0 != nil }) == word {
                stats.append("Shouts Mastered")
            }
        }
        return stats
    }

    /// The shouts with `word` in a filled slot: `Game.TeachWord` raises Shouts Learned
    /// once for each that the player did not have.
    public static func shouts(
        with word: ReferenceKey, slots: [ReferenceKey: [ReferenceKey?]]
    ) -> [ReferenceKey] {
        slots.filter { $0.value.contains(word) }.map(\.key)
    }

    /// The value used most often. The game leaves a tie open; OpenSky picks the one
    /// used last.
    public static func favorite<Value: Hashable>(of uses: [Value]) -> Value? {
        var counts: [Value: Int] = [:]
        var lastUse: [Value: Int] = [:]
        for (index, value) in uses.enumerated() {
            counts[value, default: 0] += 1
            lastUse[value] = index
        }
        return counts.max { lhs, rhs in
            (lhs.value, lastUse[lhs.key] ?? 0) < (rhs.value, lastUse[rhs.key] ?? 0)
        }?.key
    }

    public static let favoriteSchool = "Favorite School"
    /// What a "Favorite" stat shows with no use, or a form with no name.
    public static let noFavorite = "None"

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

/// What a "Favorite" stat picks from: the forms the player used last.
nonisolated public enum FavoriteUse: Int, CaseIterable, Sendable {
    case weapon = 0, spell, shout

    /// The stat each list answers; Favorite School reads the spell list too.
    public var statName: String {
        switch self {
        case .weapon: "Favorite Weapon"
        case .spell: "Favorite Spell"
        case .shout: "Favorite Shout"
        }
    }
}

/// The counted stats, keyed on the player. A stat never counted reads 0.
nonisolated public struct MiscStatsState: WorldStateComponent, Equatable, Sendable {
    /// Keyed by the catalog's spelling.
    public var values: [String: Int32]
    /// The last `recentUseLimit` uses of each kind, oldest first.
    public var recentUses: [FavoriteUse: [ReferenceKey]]

    public static let recentUseLimit = 100

    public static var componentKind: WorldStateComponentKind {
        .miscStats
    }

    public init(values: [String: Int32] = [:], recentUses: [FavoriteUse: [ReferenceKey]] = [:]) {
        self.values = values
        self.recentUses = recentUses
    }

    /// A full list drops its oldest use.
    public mutating func noteUse(_ use: FavoriteUse, of form: ReferenceKey) {
        var list = recentUses[use, default: []]
        list.append(form)
        recentUses[use] = Array(list.suffix(Self.recentUseLimit))
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

    /// Raises a "most" stat, such as "Most Gold Carried", to `value` when it is lower.
    public mutating func raise(_ name: String, to value: Int32) {
        let current = self.value(name)
        if value > current {
            increment(name, by: Int32(clamping: Int64(value) - Int64(current)))
        }
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

    public func noteFavoriteUse(_ use: FavoriteUse, of form: ReferenceKey) {
        updateMiscStats { $0.noteUse(use, of: form) }
    }

    /// Several stat changes in one write.
    public func updateMiscStats(_ change: (inout MiscStatsState) -> Void) {
        var stats = miscStats
        change(&stats)
        if stats != miscStats {
            set(stats, for: .player)
        }
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
