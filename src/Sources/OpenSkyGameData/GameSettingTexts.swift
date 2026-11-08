// String game settings one feature shows, keyed by an enum whose raw values are the
// editor IDs. A text the load order does not set reads as OpenSky's own fallback.
// See docs/formats/gmst.md.

import Foundation

/// One string setting a feature shows. The raw value is the setting's editor ID.
nonisolated public protocol GameSettingTextKey: RawRepresentable, CaseIterable, Hashable, Sendable
    where RawValue == String
{
    /// OpenSky's own words, shown when the load order has no such setting.
    var fallback: String { get }
}

nonisolated public struct GameSettingTexts<Key: GameSettingTextKey>: Equatable, Sendable {
    private var resolved: [Key: String] = [:]

    public static var vanilla: Self {
        Self()
    }

    public init() {}

    public subscript(_ key: Key) -> String {
        resolved[key] ?? key.fallback
    }

    /// Reads every key's setting from `store`, each through its own plugin's strings.
    public static func resolve(
        store: GameSettingStore, text: GameTextResolver = { _ in nil }
    ) -> Self {
        var texts = vanilla
        for key in Key.allCases {
            if let value = store.text(key.rawValue).flatMap({ text($0) }) {
                texts.resolved[key] = value
            }
        }
        return texts
    }
}
