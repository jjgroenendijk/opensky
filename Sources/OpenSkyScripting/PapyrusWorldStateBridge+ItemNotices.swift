// The HUD notice a non-silent `AddItem`, `RemoveItem`, `EquipItem`, `UnequipItem`, or
// `AddSpell` shows when it changes the player.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyScriptingInterface

extension PapyrusWorldStateBridge {
    /// Posts nothing for an NPC, or for a form with no name to show.
    func postItemNotice(
        _ form: FormID, count: Int32 = 1, to holder: ReferenceKey,
        word: KeyPath<ItemNoticeTexts, String>
    ) {
        guard holder == .player, let name = menus?.name(of: form), !name.isEmpty else { return }
        _ = presenter?.postNotification(
            ItemNoticeTexts.notice(name: name, count: count, word: itemNotices[keyPath: word])
        )
    }

    func postItemNotice(
        _ form: ReferenceKey, to holder: ReferenceKey, word: KeyPath<ItemNoticeTexts, String>
    ) {
        guard
            case let .plugin(plugin, objectID) = form,
            let local = formIDResolver?.localFormID(
                of: ResolvedFormID(plugin: plugin, objectID: objectID)
            )
        else { return }
        postItemNotice(local, to: holder, word: word)
    }
}
