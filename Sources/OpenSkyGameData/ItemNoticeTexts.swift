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
        let settings: [(String, WritableKeyPath<Self, String>)] = [
            ("sAddItemtoInventory", \.added),
            ("sRemoveItemfromInventory", \.removed),
            ("sEquipItemOnPlayer", \.equipped),
            ("sUnequipItemOnPlayer", \.unequipped),
            ("sAddItemtoSpellList", \.spellAdded)
        ]
        for (editorID, keyPath) in settings {
            if let value = store.text(editorID).flatMap({ text($0.text) }) {
                texts[keyPath: keyPath] = value
            }
        }
        return texts
    }
}
