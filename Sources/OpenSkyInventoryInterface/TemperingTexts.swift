// The quality names of an improved item, from the `sHealthDataPrefixWeap1` to `...6`
// and `sHealthDataPrefixArmo1` to `...6` string settings. See docs/engine/crafting.md.

import OpenSkyGameData

nonisolated public struct TemperingTexts: Equatable, Sendable {
    public var weaponNames = Tempering.names
    public var armorNames = Tempering.names

    public static let vanilla = Self()

    public init() {}

    /// "plain" at level 0; past the sixth name, the sixth with the extra levels.
    public func name(level: Int32, isWeapon: Bool) -> String {
        guard level > 0 else { return "plain" }
        let names = isWeapon ? weaponNames : armorNames
        let index = Int(level) - 1
        guard let last = names.last else { return "level \(level)" }
        return index < names.count ? names[index] : "\(last) +\(index - names.count + 1)"
    }

    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var settings = vanilla
        func names(_ kind: String, _ fallback: [String]) -> [String] {
            fallback.indices.map { index in
                store.text("sHealthDataPrefix\(kind)\(index + 1)").flatMap { text($0) }
                    ?? fallback[index]
            }
        }
        settings.weaponNames = names("Weap", settings.weaponNames)
        settings.armorNames = names("Armo", settings.armorNames)
        return settings
    }
}
