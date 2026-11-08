// App side of `MessageCoordinator`: finds MESG records, answers the waiting
// script, keeps help counts on the player, and passes HUD and camera calls on.
// The rules live in the coordinator. See docs/engine/messages.md.

import Foundation
import OpenSkyAudio
import OpenSkyCamera
import OpenSkyCells
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyQuests
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyScripting
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MessageWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
protocol MessageWorldHost: MenuInputConsumer {
    var audio: any AudioPort { get }
    var cinematicCamera: any CinematicCameraPort { get }
    var cinematicWorld: any CinematicCameraWorldPort { get }
    var hud: any HUDPort { get }
    var journal: any JournalPort { get }
    var journalMenu: any JournalMenuPort { get }
    var mapWorld: any MapWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    var renderer: (any RendererPort)? { get }
    var gameSession: (any GameSessionPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var scripts: any ScriptPort { get }
    var subtitles: any SubtitlePort { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

final class MessageWorldAdapter {
    unowned let game: any MessageWorldHost
    private var cachedEditorIDs: [String]?

    init(game: any MessageWorldHost) {
        self.game = game
    }

    /// Notifications and help records for the new session.
    func wire(gameSession: GameSession) {
        cachedEditorIDs = nil
        game.messages.reloadHelpRecords()
        // Frame steps run under a menu too, so notifications keep real time.
        let messages = game.messages
        let subtitles = game.subtitles
        gameSession.frameSteps.register(.messages) { [weak messages, weak subtitles] _ in
            let now = Date().timeIntervalSinceReferenceDate
            messages?.tick(time: now)
            subtitles?.advance(to: now)
        }
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
    var renderer: (any RendererPort)? {
        game.renderer
    }

    var viewCamera: FreeFlyCamera? {
        game.gameSession?.freeFlyCamera
    }

    var uiScene: UIScene {
        get { game.gameSession?.uiScene ?? .empty }
        set { game.gameSession?.uiScene = newValue }
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

    var worldNoticeTexts: GameSettingTexts<WorldNoticeText> {
        game.mapWorld.settingTexts()
    }

    func worldNoticeShown(_ notice: WorldNotice) {
        if case let .locationCleared(_, playsMusic) = notice, playsMusic {
            game.audio.musicDirector?.playSpecialMusic(.dungeonCleared)
        }
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
            let gameSession = game.gameSession,
            gameSession.movementMode.isPlayerControlled else { return false }
        gameSession.setMovementMode(firstPerson ? .walk : .thirdPerson)
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
