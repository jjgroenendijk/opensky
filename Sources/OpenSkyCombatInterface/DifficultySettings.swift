// The six difficulty levels and their damage and experience multipliers. The
// GMSTs are `fDiffMultHPByPC<suffix>` (damage the player deals),
// `fDiffMultHPToPC<suffix>` (damage the player takes), and `fDiffMultXP<suffix>`.
// Most are not in the plugins; the fallback is the UESP "Skyrim:Damage" table.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPhysics

nonisolated public enum DifficultyLevel: Int, CaseIterable, Sendable {
    case novice, apprentice, adept, expert, master, legendary

    public static let `default` = Self.adept

    /// The GMST suffix, in the order the menu lists the levels.
    public var suffix: String {
        switch self {
        case .novice: "VE"
        case .apprentice: "E"
        case .adept: "N"
        case .expert: "H"
        case .master: "VH"
        case .legendary: "L"
        }
    }

    /// The level a stored menu index names; an index out of range is Adept.
    public init(index: Int) {
        self = Self(rawValue: index) ?? .default
    }
}

nonisolated public struct DifficultyMultipliers: Equatable, Sendable {
    public let damageByPlayer: MovementSetting
    public let damageToPlayer: MovementSetting
    /// Divides Destruction experience above Adept; 1 at and below it.
    public let experience: MovementSetting

    public init(
        damageByPlayer: MovementSetting, damageToPlayer: MovementSetting,
        experience: MovementSetting
    ) {
        self.damageByPlayer = damageByPlayer
        self.damageToPlayer = damageToPlayer
        self.experience = experience
    }
}

nonisolated public struct DifficultySettings: Equatable, Sendable {
    public let levels: [DifficultyLevel: DifficultyMultipliers]

    public init(levels: [DifficultyLevel: DifficultyMultipliers]) {
        self.levels = levels
    }

    public func multipliers(_ level: DifficultyLevel) -> DifficultyMultipliers {
        levels[level] ?? Self.fallback(level, source: "UESP Skyrim:Damage")
    }

    /// UESP "Skyrim:Damage", Difficulty Level: NPC damage taken, then player damage taken.
    static let uespTable: [DifficultyLevel: (byPlayer: Float, toPlayer: Float)] = [
        .novice: (2, 0.5), .apprentice: (1.5, 0.75), .adept: (1, 1),
        .expert: (0.75, 1.5), .master: (0.5, 2), .legendary: (0.25, 3)
    ]

    public static let synthetic = DifficultySettings(levels: Dictionary(
        uniqueKeysWithValues: DifficultyLevel.allCases.map {
            ($0, fallback($0, source: "OpenSky synthetic"))
        }
    ))

    private static func fallback(
        _ level: DifficultyLevel,
        source: String
    ) -> DifficultyMultipliers {
        let row = uespTable[level] ?? (1, 1)
        return DifficultyMultipliers(
            damageByPlayer: MovementSetting(value: row.byPlayer, source: source),
            damageToPlayer: MovementSetting(value: row.toPlayer, source: source),
            experience: MovementSetting(value: 1, source: source)
        )
    }

    /// Every level from `store`. A missing GMST falls back to the UESP value, and
    /// a missing experience GMST to 1, which changes nothing.
    public static func resolve(store: GameSettingStore) -> DifficultySettings {
        let levels = DifficultyLevel.allCases.map { level in
            let row = uespTable[level] ?? (1, 1)
            return (level, DifficultyMultipliers(
                damageByPlayer: setting("fDiffMultHPByPC\(level.suffix)", store, row.byPlayer),
                damageToPlayer: setting("fDiffMultHPToPC\(level.suffix)", store, row.toPlayer),
                experience: setting("fDiffMultXP\(level.suffix)", store, 1)
            ))
        }
        return DifficultySettings(levels: Dictionary(uniqueKeysWithValues: levels))
    }

    private static func setting(_ editorID: String, _ store: GameSettingStore, _ fallback: Float)
        -> MovementSetting
    {
        guard let resolved = store.setting(editorID: editorID) else {
            return MovementSetting(value: fallback, source: "UESP Skyrim:Damage")
        }
        guard
            case let GameSetting.Value.float(value) = resolved.setting.value,
            value.isFinite, value >= 0
        else {
            return MovementSetting(value: fallback, source: "UESP Skyrim:Damage")
        }
        return MovementSetting(value: value, source: resolved.sourcePlugin)
    }
}

nonisolated public enum DifficultyDamage {
    /// The one place difficulty touches health damage. Damage the player deals is
    /// multiplied by `damageByPlayer`, damage the player takes by `damageToPlayer`.
    /// Damage between two other actors, or from the player to themself, is unchanged.
    public static func scaled(
        _ amount: Float, attackerIsPlayer: Bool, targetIsPlayer: Bool,
        multipliers: DifficultyMultipliers
    ) -> Float {
        switch (attackerIsPlayer, targetIsPlayer) {
        case (true, false): amount * multipliers.damageByPlayer.value
        case (false, true): amount * multipliers.damageToPlayer.value
        default: amount
        }
    }

    /// Destruction experience: divided above Adept, unchanged at and below it
    /// (UESP "Skyrim:Leveling", Destruction note).
    public static func destructionExperience(
        _ experience: Float, level: DifficultyLevel, multipliers: DifficultyMultipliers
    ) -> Float {
        guard level.rawValue > DifficultyLevel.adept.rawValue else { return experience }
        let divisor = multipliers.experience.value
        return divisor > 0 ? experience / divisor : experience
    }
}
