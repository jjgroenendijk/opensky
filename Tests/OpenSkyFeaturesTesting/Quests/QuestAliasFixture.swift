// Alias tables for suites that read quest aliases but do not test how a quest
// fills them, so they need no quest runtime.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

public enum QuestAliasFixture {
    /// A resolution where each quest in `fills` holds the given references, as
    /// a started quest's table reads. A quest `store` cannot key is left out.
    public static func resolution(
        store: QuestStore,
        fills: [FormID: [UInt32: ReferenceKey]]
    ) -> QuestAliasResolution {
        var tables: [ReferenceKey: QuestAliasState] = [:]
        for (quest, aliases) in fills {
            guard let key = store.key(for: quest) else { continue }
            tables[key] = QuestAliasState(
                fills: aliases.map { QuestAliasFill(aliasID: $0.key, reference: $0.value) }
            )
        }
        return QuestAliasResolution(defaults: store, tables: tables)
    }
}
