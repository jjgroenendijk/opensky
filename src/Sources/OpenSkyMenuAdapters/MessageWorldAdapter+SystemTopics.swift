// The System page's Help and Installed Content topics, read from the load order.
// The help topics are the messages of the DOBJ `HMPC` form list.

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
        switch page {
        case .help:
            let list = menus.helpManual.flatMap { data.formListStore?.flattened($0) }
            let text = MessageWorldAdapter.Text(game: game)
            let messages = (list?.entries ?? []).compactMap { entry in
                entry.flatMap { text.buildMessage(ReferenceKey(resolved: $0), arguments: []) }
            }
            return SystemMenuTopic.help(messages)
        case .installedContent:
            return SystemMenuTopic.installedContent(menus.installedPlugins)
        default:
            return []
        }
    }
}
