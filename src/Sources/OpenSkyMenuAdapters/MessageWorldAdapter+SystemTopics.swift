// The System page's Help and Installed Content topics, read from the load order.
// Each is a list of messages: the DOBJ `HMPC` form list for Help, `HMCC` for Installed Content.
// DLC and Creation scripts add their own help topics to the list with `AddForm`.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface

extension MessageWorldAdapter: SystemMenuTopicSource {
    public func systemMenuTopics(_ page: SystemMenuPage) -> [SystemMenuTopic] {
        records.systemMenuTopics(page)
    }
}

extension MessageRecordReads {
    func systemMenuTopics(_ page: SystemMenuPage) -> [SystemMenuTopic] {
        guard let data = game.menuRecords, let menus = data.menuRecords else { return [] }
        let text = MessageWorldAdapter.Text(game: game)
        func messages(_ list: ResolvedFormID?) -> [BuiltMessage] {
            guard let list else { return [] }
            let entries = data.formListStore?.flattened(list)?.entries ?? []
            let added = game.worldState
                .component(ScriptedReferenceState.self, for: ReferenceKey(resolved: list))?
                .addedForms ?? []
            let keys = entries.compactMap { $0.map(ReferenceKey.init(resolved:)) }
            let extra = added.filter { !keys.contains($0) }
            return (keys + extra).compactMap { text.buildMessage($0, arguments: []) }
        }
        switch page {
        case .help:
            return SystemMenuTopic.help(messages(menus.helpManual))
        case .installedContent:
            return SystemMenuTopic.installedContent(messages(menus.installedContent))
        default:
            return []
        }
    }
}
