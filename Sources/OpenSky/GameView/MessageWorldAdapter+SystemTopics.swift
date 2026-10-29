// The System page's Help and Installed Content topics, read from the load order.
// The help topics are the messages of the DOBJ `HMPC` form list.

import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus

extension MessageWorldAdapter: SystemMenuTopicSource {
    func systemMenuTopics(_ page: SystemMenuPage) -> [SystemMenuTopic] {
        guard let data = game.worldData, let menus = data.menuRecords else { return [] }
        switch page {
        case .help:
            let list = menus.helpManual.flatMap { data.formListStore?.flattened($0) }
            let messages = (list?.entries ?? []).compactMap { entry in
                entry.flatMap { buildMessage(ReferenceKey(resolved: $0), arguments: []) }
            }
            return SystemMenuTopic.help(messages)
        case .installedContent:
            return SystemMenuTopic.installedContent(menus.installedPlugins)
        default:
            return []
        }
    }
}
