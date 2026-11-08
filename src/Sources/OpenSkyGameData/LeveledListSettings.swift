// The game settings that scale a leveled-list roll: the leveled-actor difficulty
// multipliers, the encounter-level adjustments, and the special loot formula
// (<https://ck.uesp.net/wiki/LeveledCharacter>, <https://ck.uesp.net/wiki/LeveledItem>).
// See docs/engine/leveled-lists.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct LeveledListSettings: Equatable, Sendable {
    /// `fLeveledActorMult` by difficulty: easy, medium, hard, very hard.
    public var actorMultEasy = 0.33
    public var actorMultMedium = 0.67
    public var actorMultHard: Double = 1
    public var actorMultVeryHard = 1.25
    public var levelScalingMult: Double = 1
    public var calcLevelAdjustUp = 0
    public var calcLevelAdjustDown = 0
    public var specialLoot = SpecialLootSettings()

    /// The `Skyrim.esm` values, for a session without a settings table.
    public static let fallback = LeveledListSettings()

    public init() {}

    public static func resolve(store: GameSettingStore) -> LeveledListSettings {
        var settings = fallback
        func read(_ editorID: String) -> Double? {
            switch store.setting(editorID: editorID)?.setting.value {
            case let .float(number)?: number.isFinite ? Double(number) : nil
            case let .integer(number)?: Double(number)
            default: nil
            }
        }
        settings.actorMultEasy = read("fLeveledActorMultEasy") ?? settings.actorMultEasy
        settings.actorMultMedium = read("fLeveledActorMultMedium") ?? settings.actorMultMedium
        settings.actorMultHard = read("fLeveledActorMultHard") ?? settings.actorMultHard
        settings.actorMultVeryHard = read("fLeveledActorMultVeryHard")
            ?? settings.actorMultVeryHard
        settings.levelScalingMult = read("fLevelScalingMult") ?? settings.levelScalingMult
        settings.calcLevelAdjustUp = read("iCalcLevelAdjustUp").map { Int($0) }
            ?? settings.calcLevelAdjustUp
        settings.calcLevelAdjustDown = read("iCalcLevelAdjustDown").map { Int($0) }
            ?? settings.calcLevelAdjustDown
        settings.specialLoot = SpecialLootSettings(read: read)
        return settings
    }

    /// The multiplier a placed leveled actor's difficulty applies to its encounter level.
    public func actorMult(_ difficulty: LeveledActorDifficulty) -> Double {
        switch difficulty {
        case .easy: actorMultEasy
        case .medium: actorMultMedium
        case .hard: actorMultHard
        case .veryHard: actorMultVeryHard
        case .none: 1
        }
    }
}

/// The `fSpecialLoot` settings. `Skyrim.esm` sets four of them; the rest are 0.
nonisolated public struct SpecialLootSettings: Equatable, Sendable {
    public var minPCLevelMult = 0.6
    public var minPCLevelBase: Double = 0
    public var minZoneLevelBase: Double = 0
    public var minZoneLevelMult = 0.4
    public var maxPCLevelMult: Double = 0
    public var maxPCLevelBase: Double = 0
    public var maxZoneLevelBase: Double = 0
    public var maxZoneLevelMult: Double = 1
    public var weighting: Double = 4

    public init() {}

    init(read: (String) -> Double?) {
        func value(_ name: String, _ fallback: Double) -> Double {
            read("fSpecialLoot\(name)") ?? fallback
        }
        let defaults = SpecialLootSettings()
        minPCLevelMult = value("MinPCLevelMult", defaults.minPCLevelMult)
        minPCLevelBase = value("MinPCLevelBase", defaults.minPCLevelBase)
        minZoneLevelBase = value("MinZoneLevelBase", defaults.minZoneLevelBase)
        minZoneLevelMult = value("MinZoneLevelMult", defaults.minZoneLevelMult)
        maxPCLevelMult = value("MaxPCLevelMult", defaults.maxPCLevelMult)
        maxPCLevelBase = value("MaxPCLevelBase", defaults.maxPCLevelBase)
        maxZoneLevelBase = value("MaxZoneLevelBase", defaults.maxZoneLevelBase)
        maxZoneLevelMult = value("MaxZoneLevelMult", defaults.maxZoneLevelMult)
        weighting = value("Weighting", defaults.weighting)
    }

    /// The level a Special Loot list rolls at. `draw` is uniform in -0.5 ..< 0.5.
    /// The CK formula raises the draw to `weighting`; OpenSky raises its size, so a
    /// fractional weighting stays defined. For the vanilla weighting of 4 both agree.
    public func level(playerLevel: Int, inputLevel: Int, draw: Double) -> Double {
        let player = Double(playerLevel)
        let input = Double(inputLevel)
        let low = player * minPCLevelMult + minPCLevelBase + minZoneLevelBase
            + input * minZoneLevelMult
        let high = player * maxPCLevelMult + maxPCLevelBase + maxZoneLevelBase
            + input * maxZoneLevelMult
        return low + (high - low) * pow(abs(draw), weighting)
    }
}
