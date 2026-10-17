// The soul sizes a soul gem names, from the `sSoulLevelName*` string settings, and
// its "Filled with %s Soul" line from `sSoulLevel`. See docs/formats/item-records.md.

import OpenSkyFormatsESM

nonisolated public struct SoulTexts: Equatable, Sendable {
    public var names = suffixes
    /// `%s` is the soul's name.
    public var filled = "Filled with %s Soul"
    public var empty = "Empty"

    public static let vanilla = Self()

    public init() {}

    public func name(of level: SoulLevel) -> String {
        names[level.rawValue] ?? "\(level)"
    }

    /// "Filled with Petty Soul", or the empty word for a gem with no soul.
    public func contents(_ soul: SoulLevel?) -> String {
        guard let soul, soul != .empty else { return empty }
        return SettingTextFormat.fill(filled, [name(of: soul)])
    }

    static let suffixes: [UInt8: String] = [
        1: "Petty", 2: "Lesser", 3: "Common", 4: "Greater", 5: "Grand"
    ]

    public static func resolve(
        store: GameSettingStore, text: (LString) -> String? = { _ in nil }
    ) -> Self {
        var texts = vanilla
        for (level, suffix) in suffixes {
            if let name = store.text("sSoulLevelName\(suffix)").flatMap({ text($0.text) }) {
                texts.names[level] = name
            }
        }
        store.read("sSoulLevel", into: &texts, \.filled, text: text)
        store.read("sEmpty", into: &texts, \.empty, text: text)
        return texts
    }
}
