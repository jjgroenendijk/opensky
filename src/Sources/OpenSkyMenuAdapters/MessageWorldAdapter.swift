// App side of `MessageCoordinator`: finds MESG records, answers the waiting
// script, keeps help counts on the player, and passes HUD and camera calls on.
// The rules live in the coordinator. See docs/engine/messages.md.

public import Foundation
import OpenSkyAudio
import OpenSkyCamera
import OpenSkyCells
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldConditions
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MessageWorldAdapter` reads from the session. `GameViewController` conforms.
@MainActor
public protocol MessageWorldHost: MenuInputConsumer, SendableMetatype {
    var audio: any AudioPort { get }
    var hud: any HUDPort { get }
    var journal: any JournalPort { get }
    var journalMenu: any JournalMenuPort { get }
    var mapWorld: any MapWorldPort { get }
    var messages: any MessageCoordinatorPort { get }
    var runtimeState: any RuntimeStatePort { get }
    var scripts: any ScriptPort { get }
    var subtitles: any SubtitlePort { get }
    var menuRecords: (any MenuRecordsPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

public final class MessageWorldAdapter {
    public let game: any MessageWorldHost
    let records: MessageRecordReads

    public let cameraEffectsHost: any MessageCameraEffectsHost

    public var cameraEffects: MessageCameraEffectsAdapter {
        MessageCameraEffectsAdapter(game: cameraEffectsHost
        )
    }

    public let now: () -> Date

    public init(game: some MessageWorldHost & MessageCameraEffectsHost, now: @escaping () -> Date) {
        self.now = now
        cameraEffectsHost = game
        self.game = game
        records = MessageRecordReads(game: game)
    }
}

extension MessageWorldAdapter: MessageWorld {
    public func buildMessage(_ key: ReferenceKey, arguments: [Float]) -> BuiltMessage? {
        text.buildMessage(key, arguments: arguments)
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
        records.messageEditorIDs
    }

    public func messageKey(editorID: String) -> ReferenceKey? {
        records.messageKey(editorID: editorID)
    }

    public var menuInputConsumer: (any MenuInputConsumer)? {
        game
    }
}

extension MessageWorldAdapter: MessageWorldPort {}

/// The MESG editor IDs, read once a session, and the System page topics.
final class MessageRecordReads {
    let game: any MessageWorldHost
    var cachedEditorIDs: [String]?

    init(game: any MessageWorldHost) {
        self.game = game
    }

    private var presentation: PresentationRecordStore? {
        game.menuRecords?.presentationRecords
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
}
