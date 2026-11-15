// The System page's Help and Installed Content topics, read from the load order.
// Each is a list of messages: the DOBJ `HMPC` form list for Help, `HMCC` for Installed Content.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyMenus
public import OpenSkyMenusInterface

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
            let entries = list.flatMap { data.formListStore?.flattened($0) }?.entries ?? []
            return entries.compactMap { entry in
                entry.flatMap { text.buildMessage(ReferenceKey(resolved: $0), arguments: []) }
            }
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
