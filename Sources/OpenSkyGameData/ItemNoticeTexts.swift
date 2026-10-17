// The HUD notices a script's item and spell changes show the player, from the
// `sAddItemtoInventory` and related string settings. See docs/engine/papyrus-runtime.md.

import OpenSkyFormatsESM

nonisolated public struct ItemNoticeTexts: Equatable, Sendable {
    public var added = "added"
    public var removed = "removed"
    public var equipped = "was equipped"
    public var unequipped = "was unequipped"
    public var spellAdded = "added"

    public static let vanilla = Self()

    public init() {}

    /// "Iron Sword added", or "Iron Arrow (12) added" for more than one.
    public static func notice(name: String, count: Int32 = 1, word: String) -> String {
        count > 1 ? "\(name) (\(count)) \(word)" : "\(name) \(word)"
    }

    public static func resolve(
        store: GameSettingStore, text: (LString) -> String? = { _ in nil }
    ) -> Self {
        var texts = vanilla
        store.read("sAddItemtoInventory", into: &texts, \.added, text: text)
        store.read("sRemoveItemfromInventory", into: &texts, \.removed, text: text)
        store.read("sEquipItemOnPlayer", into: &texts, \.equipped, text: text)
        store.read("sUnequipItemOnPlayer", into: &texts, \.unequipped, text: text)
        store.read("sAddItemtoSpellList", into: &texts, \.spellAdded, text: text)
        return texts
    }
}
