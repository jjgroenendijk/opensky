// App side of `MessageCoordinator`: finds MESG records, answers the waiting
// script, keeps help counts on the player, and passes HUD and camera calls on.
// The rules live in the coordinator. See docs/engine/messages.md.

import Foundation
import OpenSkyAudio
import OpenSkyCamera
public import OpenSkyCells
import OpenSkyConditions
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyQuests
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MessageWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol MessageWorldHost: MenuInputConsumer {
    var audio: any AudioPort { get }
    var hud: any HUDPort { get }
    var journal: any JournalPort { get }
    var journalMenu: any JournalMenuPort { get }
    var mapWorld: any MapWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    var runtimeState: any RuntimeStatePort { get }
    var scripts: any ScriptPort { get }
    var subtitles: any SubtitlePort { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

public final class MessageWorldAdapter {
    public unowned let game: any MessageWorldHost
    var cachedEditorIDs: [String]?

    public let cameraEffectsHost: any MessageCameraEffectsHost

    public var cameraEffects: MessageCameraEffectsAdapter {
        MessageCameraEffectsAdapter(
            owner: self,
            game: cameraEffectsHost
        )
    }

    public init(game: some MessageWorldHost & MessageCameraEffectsHost) {
        cameraEffectsHost = game
        self.game = game
    }

    private var presentation: PresentationRecordStore? {
        game.worldData?.presentationRecords
    }

    /// The MESG's QNAM owner, whose aliases the text's tags name.
    private func quest(of message: ResolvedRecord<GameMessage>) -> Quest? {
        guard
            let store = presentation,
            let link = store.messages.link(message.record.quest, from: message), !link.isDangling,
            let quests = game.worldData?.questStore,
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

extension MessageWorldAdapter: MessageWorld {
    public func buildMessage(_ key: ReferenceKey, arguments: [Float]) -> BuiltMessage? {
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

    public func answerMessage(token: UInt64, buttonIndex: Int) {
        game.scripts.runtime?.scheduler.answer(token, returning: .integer(Int32(buttonIndex)))
    }

    public var helpMessageRecords: [String: HelpMessageRecord] {
        get { game.worldState.component(HelpMessageState.self, for: .player)?.records ?? [:] }
        set { game.worldState.set(HelpMessageState(records: newValue), for: .player) }
    }

    public func showHUDNotification(_ text: String) {
        game.hud.showNotification(text)
    }

    public var worldNoticeTexts: GameSettingTexts<WorldNoticeText> {
        game.mapWorld.settingTexts()
    }

    public func worldNoticeShown(_ notice: WorldNotice) {
        if case let .locationCleared(_, playsMusic) = notice, playsMusic {
            game.audio.musicDirector?.playSpecialMusic(.dungeonCleared)
        }
    }

    public func setHUDHelpMessage(_ text: String?) {
        game.hud.setHelpMessage(text)
    }

    public var messageEditorIDs: [String] {
        if let cachedEditorIDs {
            return cachedEditorIDs
        }
        let names = presentation?.messages.records.compactMap(\.record.editorID).sorted() ?? []
        cachedEditorIDs = names
        return names
    }

    public func messageKey(editorID: String) -> ReferenceKey? {
        presentation?.messages.record(editorID: editorID).map { ReferenceKey(resolved: $0.id) }
    }

    public var menuInputConsumer: (any MenuInputConsumer)? {
        game
    }
}

extension MessageWorldAdapter: MessageWorldPort {}
