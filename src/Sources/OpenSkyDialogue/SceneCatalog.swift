// The scenes the runtime can play, in the FormID space of the quest and dialogue
// stores, with the session-stable key their state is filed under.
// See docs/engine/scenes.md.

import Foundation
public import OpenSkyDialogueInterface
public import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension SceneCatalog {
    public func scene(_ id: FormID) -> CatalogScene? {
        byFormID[id.rawValue]
    }

    func scene(editorID: String) -> CatalogScene? {
        byEditorID[editorID.lowercased()].flatMap { byFormID[$0] }
    }

    /// Scenes whose PNAM names `quest`, in FormID order.
    public func scenes(ofQuest quest: FormID) -> [CatalogScene] {
        (byQuest[quest.rawValue] ?? []).compactMap { byFormID[$0] }
    }
}

nonisolated extension SceneCatalog {
    var count: Int {
        byFormID.count
    }
}
