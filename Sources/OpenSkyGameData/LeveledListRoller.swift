// What a leveled roll reads besides the list: the live player level, the
// settings, the `LVLG` chance-none globals, and the encounter zone and
// difficulty each leveled actor base and each cell was last built with. Every
// resolver of one session shares one roller, so they all pick the same entry.
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
        var cells: [CellSceneLocation: EncounterZone] = [:]
    }

    private let state = Mutex(State())

    public init() {}

    /// The newest build of a base wins, as the game rolls again when a cell loads.
    public func record(actor base: FormID, _ placement: LeveledActorPlacement) {
        state.withLock { $0.actors[base.rawValue] = placement }
    }

    public func record(cell: CellSceneLocation, zone: EncounterZone?) {
        state.withLock { $0.cells[cell] = zone }
    }

    public func placement(of base: FormID) -> LeveledActorPlacement? {
        state.withLock { $0.actors[base.rawValue] }
    }

    public func zone(of cell: CellSceneLocation) -> EncounterZone? {
        state.withLock { $0.cells[cell] }
    }
}

/// Everything an actor base's rolls read besides the records, so a memo of a
/// derived baseline can tell when to derive again.
nonisolated public struct LeveledActorRollKey: Hashable, Sendable {
    public let base: FormID
    public let playerLevel: Int
    public let encounterLevel: Int
    public let difficulty: LeveledActorDifficulty
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

    /// A request at the encounter level of a place in `zone`.
    public func request(in zone: EncounterZone?) -> LeveledRequest {
        let player = playerLevel.level
        return LeveledRequest(
            level: EncounterLevel.level(playerLevel: player, zone: zone, settings: settings),
            playerLevel: player
        )
    }

    /// The request for the lists an actor base carries: its outfit, items, and spells.
    public func request(forActor base: FormID) -> LeveledRequest {
        request(in: placements.placement(of: base)?.zone)
    }

    public func rollKey(forActor base: FormID) -> LeveledActorRollKey {
        let placement = placements.placement(of: base)
        let request = request(in: placement?.zone)
        return LeveledActorRollKey(
            base: base, playerLevel: request.playerLevel, encounterLevel: request.level,
            difficulty: placement?.difficulty ?? .none
        )
    }

    /// The request for a container in `cell`; an unknown cell has no zone.
    public func request(forCell cell: CellSceneLocation?) -> LeveledRequest {
        request(in: cell.flatMap(placements.zone(of:)))
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

    /// The `LVLN` entry the actor walk from `base` takes, at the zone and difficulty
    /// `base` was last built with.
    public func actorEntry(_ list: LeveledList, for base: FormID) -> LeveledList.Entry? {
        let placement = placements.placement(of: base)
        var random = SplitMix64(
            seed: LeveledListRoll.seed(UInt64(base.rawValue), UInt64(list.formID.rawValue))
        )
        return LeveledListRoll.actorEntry(
            list,
            encounterLevel: request(in: placement?.zone).level,
            difficulty: placement?.difficulty ?? .none,
            settings: settings,
            random: &random
        )
    }
}
