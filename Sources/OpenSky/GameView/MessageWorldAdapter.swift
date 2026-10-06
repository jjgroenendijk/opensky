// App side of `MessageCoordinator`: finds MESG records, answers the waiting
// script, keeps help counts on the player, and passes HUD and camera calls on.
// The rules live in the coordinator. See docs/engine/messages.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyQuests
import OpenSkyRendering
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkyWorld
import OpenSkyWorldState

final class MessageWorldAdapter {
    unowned let game: GameViewController
    private var cachedEditorIDs: [String]?

    init(game: GameViewController) {
        self.game = game
    }

    /// Gives the Papyrus bridge its presenter, once the VM exists.
    func wire(renderer: Renderer) {
        game.scripts.bridge?.presenter = game.messages
        cachedEditorIDs = nil
        game.messages.attach(world: self)
        // `onFrame` runs under a menu too, so notifications keep real time.
        renderer.onFrame.add { [weak messages = game.messages, weak subtitles = game.subtitles] _ in
            let now = Date().timeIntervalSinceReferenceDate
            messages?.tick(time: now)
            subtitles?.advance(to: now)
        }
    }

    private var presentation: PresentationRecordStore? {
        (game.worldData as? PresentationDataProviding)?.presentationRecords
    }

    /// The MESG's QNAM owner, whose aliases the text's tags name.
    private func quest(of message: ResolvedRecord<GameMessage>) -> Quest? {
        guard
            let store = presentation,
            let link = store.messages.link(message.record.quest, from: message), !link.isDangling,
            let quests = (game.worldData as? QuestDataProviding)?.questStore,
            let id = quests.formID(for: ReferenceKey(resolved: link.target))
        else { return nil }
        return quests.quest(id)
    }

    /// A message's text IDs point into the tables of the plugin whose record won.
    private func builder(plugin: String) -> MessageTextBuilder {
        let naming = game.journalMenu.questRuntime.map { game.journalMenu.aliasNaming(runtime: $0) }
        return MessageTextBuilder(
            strings: game.journal.strings?.scoped(to: plugin),
            naming: naming ?? .none
        )
    }
}

extension MessageWorldAdapter: MessageWorld {
    var renderer: Renderer? {
        game.renderer
    }

    func buildMessage(_ key: ReferenceKey, arguments: [Float]) -> BuiltMessage? {
        guard let message = presentation?.messages.record(key) else { return nil }
        var context = game.runtimeState.conditionContext()
        context.subject = .player
        return builder(plugin: message.sourcePlugin).build(
            message.record,
            arguments: arguments,
            quest: quest(of: message),
            buttonVisible: MessageTextBuilder.conditionCheck(ConditionEvaluator(context: context))
        )
    }

    func answerMessage(token: UInt64, buttonIndex: Int) {
        game.scripts.runtime?.scheduler.answer(token, returning: .integer(Int32(buttonIndex)))
    }

    var helpMessageRecords: [String: HelpMessageRecord] {
        get { game.worldState.component(HelpMessageState.self, for: .player)?.records ?? [:] }
        set { game.worldState.set(HelpMessageState(records: newValue), for: .player) }
    }

    func showHUDNotification(_ text: String) {
        game.hud.showNotification(text)
    }

    func setHUDHelpMessage(_ text: String?) {
        game.hud.setHelpMessage(text)
    }

    func shakeCamera(source: ReferenceKey?, strength: Float, duration: Float) -> Bool {
        let position = source.flatMap { game.cinematicWorld.anchorPosition(of: $0) }
        return game.cinematicCamera.startShake(
            source: position,
            strength: strength,
            duration: duration
        )
    }

    func forceCameraMode(firstPerson: Bool) -> Bool {
        guard
            let renderer = game.renderer,
            renderer.movementMode.isPlayerControlled else { return false }
        renderer.setMovementMode(firstPerson ? .walk : .thirdPerson)
        return true
    }

    var messageEditorIDs: [String] {
        if let cachedEditorIDs {
            return cachedEditorIDs
        }
        let names = presentation?.messages.records.compactMap(\.record.editorID).sorted() ?? []
        cachedEditorIDs = names
        return names
    }

    func messageKey(editorID: String) -> ReferenceKey? {
        presentation?.messages.record(editorID: editorID).map { ReferenceKey(resolved: $0.id) }
    }

    var menuInputConsumer: (any MenuInputConsumer)? {
        game
    }
}
