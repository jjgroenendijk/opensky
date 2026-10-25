// What a leveled roll reads besides the list: the player level, the settings,
// the `LVLG` chance-none globals, and the encounter zone and difficulty each
// placed reference was built with. Every resolver of one session shares one
// roller, and one owner's `LeveledRoll` gives each of them the same pick.
// See docs/engine/leveled-lists.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import Synchronization

/// Where a leveled actor base was placed: the zone of its cell and its `XLCM`.
nonisolated public struct LeveledActorPlacement: Equatable, Sendable {
    public var zone: EncounterZone?
    public var difficulty: LeveledActorDifficulty

    public init(zone: EncounterZone?, difficulty: LeveledActorDifficulty) {
        self.zone = zone
        self.difficulty = difficulty
    }
}

/// The placements cell builds record. Locked, because the build queue writes them
/// and main-actor resolvers read them.
nonisolated public final class LeveledPlacements: Sendable {
    private struct State {
        var actors: [UInt32: LeveledActorPlacement] = [:]
        var references: [ReferenceKey: LeveledActorPlacement] = [:]
        var cells: [CellSceneLocation: EncounterZone] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    /// The newest build of a base wins, as the game rolls again when a cell loads.
    public func record(actor base: FormID, _ placement: LeveledActorPlacement) {
        state.withLock { $0.actors[base.rawValue] = placement }
    }

    public func record(reference: ReferenceKey, _ placement: LeveledActorPlacement) {
        state.withLock { $0.references[reference] = placement }
    }

    public func record(cell: CellSceneLocation, zone: EncounterZone?) {
        state.withLock { $0.cells[cell] = zone }
    }

    public func placement(of base: FormID) -> LeveledActorPlacement? {
        state.withLock { $0.actors[base.rawValue] }
    }

    public func placement(ofReference reference: ReferenceKey) -> LeveledActorPlacement? {
        state.withLock { $0.references[reference] }
    }

    public func zone(of cell: CellSceneLocation) -> EncounterZone? {
        state.withLock { $0.cells[cell] }
    }
}

/// The seed and levels one owner's rolls read. Every resolver that gets the same
/// roll picks the same entries, and a memo keyed on it derives again when it changes.
nonisolated public struct LeveledRoll: Hashable, Sendable {
    public let seed: UInt64
    public let playerLevel: Int
    public let encounterLevel: Int
    public let difficulty: LeveledActorDifficulty

    public init(
        seed: UInt64, playerLevel: Int, encounterLevel: Int,
        difficulty: LeveledActorDifficulty = .none
    ) {
        self.seed = seed
        self.playerLevel = playerLevel
        self.encounterLevel = encounterLevel
        self.difficulty = difficulty
    }

    /// What an item or spell list asks at.
    public var request: LeveledRequest {
        LeveledRequest(level: encounterLevel, playerLevel: playerLevel)
    }
}

/// An actor base and the roll it resolved with, the key of a derived-baseline memo.
nonisolated public struct LeveledActorRollKey: Hashable, Sendable {
    public let base: FormID
    public let roll: LeveledRoll

    public init(base: FormID, roll: LeveledRoll) {
        self.base = base
        self.roll = roll
    }
}

nonisolated public struct LeveledListRoller: Sendable {
    public let playerLevel: PlayerLevelSource
    public let settings: LeveledListSettings
    public let placements: LeveledPlacements
    private let chanceNoneGlobal: @Sendable (FormID) -> Float?

    public init(
        playerLevel: PlayerLevelSource = PlayerLevelSource(),
        settings: LeveledListSettings = .fallback,
        placements: LeveledPlacements = LeveledPlacements(),
        chanceNoneGlobal: @escaping @Sendable (FormID) -> Float? = { _ in nil }
    ) {
        self.playerLevel = playerLevel
        self.settings = settings
        self.placements = placements
        self.chanceNoneGlobal = chanceNoneGlobal
    }

    /// The roll of an actor base with no placed reference in hand, seeded by the base.
    public func roll(forActor base: FormID) -> LeveledRoll {
        roll(
            seed: UInt64(base.rawValue), placement: placements.placement(of: base),
            playerLevel: playerLevel.level
        )
    }

    /// The roll of one placed actor or container, seeded by its key. `frozenLevel` is
    /// the player level its cell froze; nil rolls at the live level.
    public func roll(
        for reference: ReferenceKey, base: FormID?, cell: CellSceneLocation?, frozenLevel: Int?
    ) -> LeveledRoll {
        let placement = placements.placement(ofReference: reference)
            ?? base.flatMap(placements.placement(of:))
            ?? LeveledActorPlacement(zone: cell.flatMap(placements.zone(of:)), difficulty: .none)
        return roll(
            seed: LeveledListRoll.seed(text: reference.description), placement: placement,
            playerLevel: frozenLevel ?? playerLevel.level
        )
    }

    /// A placed actor's roll. Nil for the player and a generated actor.
    public func roll(of holder: ActorValueHolder, frozenLevel: Int?) -> LeveledRoll? {
        guard case let .actor(base) = holder.subject else { return nil }
        return roll(for: holder.key, base: base, cell: holder.cell, frozenLevel: frozenLevel)
    }

    private func roll(
        seed: UInt64, placement: LeveledActorPlacement?, playerLevel: Int
    ) -> LeveledRoll {
        LeveledRoll(
            seed: seed,
            playerLevel: playerLevel,
            encounterLevel: EncounterLevel.level(
                playerLevel: playerLevel, zone: placement?.zone, settings: settings
            ),
            difficulty: placement?.difficulty ?? .none
        )
    }

    /// A request at an exact level, such as a harvested plant's player level.
    public func request(atLevel level: Int) -> LeveledRequest {
        LeveledRequest(level: max(1, level), playerLevel: playerLevel.level)
    }

    /// `LVLG` when it names a global with a value, else `LVLD`.
    public func chanceNone(of list: LeveledList) -> Float {
        list.chanceNoneGlobal.flatMap(chanceNoneGlobal) ?? Float(list.chanceNone)
    }

    /// `count` asked of `list` by the owner `seed` names.
    public func roll(
        _ list: LeveledList, count: Int32, request: LeveledRequest, seed: UInt64
    ) -> [LeveledPick] {
        var random = SplitMix64(seed: LeveledListRoll.seed(seed, UInt64(list.formID.rawValue)))
        return LeveledListRoll.roll(
            list, count: count, request: request, chanceNone: chanceNone(of: list),
            settings: settings.specialLoot, random: &random
        )
    }

    /// The `LVLN` entry an actor walk takes for the owner of `roll`.
    public func actorEntry(_ list: LeveledList, roll: LeveledRoll) -> LeveledList.Entry? {
        var random = SplitMix64(seed: LeveledListRoll.seed(roll.seed, UInt64(list.formID.rawValue)))
        return LeveledListRoll.actorEntry(
            list,
            encounterLevel: roll.encounterLevel,
            difficulty: roll.difficulty,
            settings: settings,
            random: &random
        )
    }
}
