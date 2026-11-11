// The text of a MESG record: its quest, and the strings of the plugin that won.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkySessionInterface

extension MessageWorldAdapter {
    var text: Text {
        Text(game: game)
    }

    struct Text {
        let game: any MessageWorldHost

        private var presentation: PresentationRecordStore? {
            game.menuRecords?.presentationRecords
        }

        func buildMessage(_ key: ReferenceKey, arguments: [Float]) -> BuiltMessage? {
            guard let message = presentation?.messages.record(key) else { return nil }
            var context = game.runtimeState.conditionContext()
            context.subject = .player
            return builder(plugin: message.sourcePlugin).build(
                message.record,
                arguments: arguments,
                quest: quest(of: message),
                buttonVisible: MessageTextBuilder
                    .conditionCheck(ConditionEvaluator(context: context))
            )
        }

        /// The MESG's QNAM owner, whose aliases the text's tags name.
        private func quest(of message: ResolvedRecord<GameMessage>) -> Quest? {
            guard
                let store = presentation,
                let link = store.messages.link(message.record.quest, from: message),
                !link.isDangling,
                let quests = game.menuRecords?.questStore,
                let id = quests.formID(for: ReferenceKey(resolved: link.target))
            else { return nil }
            return quests.quest(id)
        }

        /// A message's text IDs point into the tables of the plugin whose record won.
        private func builder(plugin: String) -> MessageTextBuilder {
            let naming = game.journalMenu.currentAliasNaming
            return MessageTextBuilder(
                strings: game.journal.strings?.scoped(to: plugin),
                naming: naming ?? .none
            )
        }
    }
}
