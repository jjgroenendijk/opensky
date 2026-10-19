// The season a harvest rolls its `PFPC` chance in. CK wiki "Flora": the ingredient
// is given "depending upon the harvest chance set for that season".
// <https://ck.uesp.net/wiki/Flora>. See docs/engine/interaction.md.

import Foundation

nonisolated public enum HarvestSeason: Int, CaseIterable, Equatable, Sendable {
    case spring, summer, fall, winter

    /// The Tamriel month (1 = Morning Star) by its Earth month in UESP "Lore:Calendar":
    /// spring is First Seed to Second Seed, winter is Evening Star to Sun's Dawn.
    public init?(month: Int) {
        guard (1 ... 12).contains(month) else { return nil }
        self.init(rawValue: ((month + 9) % 12) / 3)
    }

    /// The string setting that names the season, such as `sSeasonSpring`.
    public var settingName: String {
        switch self {
        case .spring: "sSeasonSpring"
        case .summer: "sSeasonSummer"
        case .fall: "sSeasonFall"
        case .winter: "sSeasonWinter"
        }
    }

    /// The percent chance a plant yields in this season. Nil when `chances` holds no
    /// chance at all: six vanilla plants, such as `ChickenNest`, have 0 in every
    /// season and still yield in the game.
    public func chance(in chances: [UInt8]?) -> Float? {
        guard let chances, chances.count == 4, chances.contains(where: { $0 > 0 }) else {
            return nil
        }
        return Float(chances[rawValue])
    }

    /// Whether a harvest yields: `roll` is a number in [0, 100).
    public static func yields(chances: [UInt8]?, season: HarvestSeason?, roll: Float) -> Bool {
        guard let season, let chance = season.chance(in: chances) else { return true }
        return roll < chance
    }
}
