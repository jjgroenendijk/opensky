// The help screen's reads: help topics are MESG records found through the message
// adapter, and button names come from the player's key bindings.

import Foundation
import OpenSkyMenus

extension MenuScreensWorldAdapter: TutorialMenuWorld {
    func helpTopic(_ editorID: String) -> HelpTopic? {
        let messages = game.messageWorld
        guard
            let key = messages.messageKey(editorID: editorID),
            let built = messages.buildMessage(key, arguments: [])
        else { return nil }
        let name = editorID.dropFirst("Help".count).dropLast("Long".count)
        return HelpTopic(
            editorID: editorID,
            title: built.title.flatMap { $0.isEmpty ? nil : $0 } ?? String(name),
            text: built.text
        )
    }

    var helpTopicEditorIDs: [String] {
        game.messageWorld.messageEditorIDs.filter(HelpTopic.isTopic(editorID:))
    }

    func buttonName(forUserEvent event: String) -> String? {
        let settings = game.playerSettings
        guard
            let slot = InputBindings.slots.first(where: { $0.event == event }),
            let scanCode = settings.bindings.scanCode(for: slot.action)
        else { return nil }
        return settings.keyName(scanCode)
    }
}
