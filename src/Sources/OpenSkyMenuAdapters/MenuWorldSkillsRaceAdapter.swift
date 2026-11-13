public import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagicInterface
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldSkillsRaceAdapter` reads from the session.
@MainActor
public protocol MenuWorldSkillsRaceHost: MenuInputConsumer, SendableMetatype {
    var audio: any AudioPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var mapWorld: any MapWorldPort { get }
    var player: any PlayerPort { get }
    var playerBeastForm: PlayerBeastForm { get }
    var progression: any ProgressionPort { get }
    var renderer: (any RendererPort)? { get }
    var scripts: any ScriptPort { get }
    var swfMovies: any SWFMovieSourcePort { get }
    var menuRecords: (any MenuRecordsPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MenuWorldAdapter`, over its own narrow host.
public struct MenuWorldSkillsRaceAdapter {
    public let game: any MenuWorldSkillsRaceHost
    let state: MenuPartState
}

extension MenuWorldSkillsRaceAdapter {
    /// Nil until leveling is wired, so the menu does not open on an empty card.
    var skillsMenuSource: (any SkillsMenuSource)? {
        game.progression.leveling == nil ? nil : game.progression
    }

    var menuInputConsumer: (any MenuInputConsumer)? {
        game
    }

    var isPlayerInBeastForm: Bool {
        game.playerBeastForm.isBeast
    }

    public func playLevelUpMusic() {
        game.audio.musicDirector?.playSpecialMusic(.levelUp)
    }

    var skillsMenuTexts: GameSettingTexts<SkillsMenuText> {
        game.mapWorld.settingTexts()
    }

    public var perkSkySource: PerkSkySource? {
        if state.perkSky == nil, let files = game.menuRecords?.scriptFileSystem {
            state.perkSky = PerkSkySource(fileSystem: files)
        }
        return state.perkSky
    }

    var perkSkySettings: PerkSkySettings {
        let values = game.mapWorld.records?.statsSettings ?? [:]
        return PerkSkySettings { values[$0] }
    }

    var renderer: (any RendererPort)? {
        game.renderer
    }

    var titleSettings: TitleMenuSettings {
        game.menuRecords.map {
            TitleMenuSettings.resolve(store: $0.gameSettings) { [game] in game.mapWorld.text($0) }
        } ?? .vanilla
    }

    var gameFiles: (any GameFileSource)? {
        game.swfMovies.fileSystem
    }

    var viewCamera: FreeFlyCamera? {
        game.gameSession?.freeFlyCamera
    }

    var uiScene: UIScene {
        get { game.gameSession?.uiScene ?? .empty }
        nonmutating set { game.gameSession?.uiScene = newValue }
    }

    public var playerIdentity: PlayerIdentityState? {
        game.worldState.component(PlayerIdentityState.self, for: .player) ?? recordIdentity
    }

    var playableRaces: [RaceChoice] {
        races.playableRaces
    }

    var raceMenuLabels: RaceMenuLabels {
        races.raceMenuLabels
    }

    public func raceMenuOptions(race: FormID, isFemale: Bool) -> RaceMenuOptions {
        races.raceMenuOptions(race: race, isFemale: isFemale)
    }

    public func applyPlayerIdentity(_ identity: PlayerIdentityState) {
        game.worldState.set(identity, for: .player)
        game.player.refreshBody()
    }

    public func racePresets(race: FormID, isFemale: Bool) -> [RacePreset] {
        races.racePresets(race: race, isFemale: isFemale)
    }

    public func raceMenuClosed() {
        game.scripts.runtime?.queueRaceSwitchComplete(actor: .player)
    }
}

extension MenuWorldSkillsRaceAdapter {
    var races: RaceMenuReads {
        RaceMenuReads(game: game)
    }

    public var identityRecords: ActorIdentityRecords? {
        races.identityRecords
    }

    var recordIdentity: PlayerIdentityState? {
        races.recordIdentity
    }
}

/// The playable races, their head options, and the identities the race menu starts from.
struct RaceMenuReads {
    let game: any MenuWorldSkillsRaceHost

    var playableRaces: [RaceChoice] {
        (game.mapWorld.records?.playableRaces ?? []).map {
            RaceChoice(
                formID: $0.formID,
                name: game.mapWorld.text($0.name) ?? $0.editorID ?? "\($0.formID)",
                description: game.mapWorld.text($0.details.description, kind: .dlstrings) ?? ""
            )
        }
    }

    var raceMenuLabels: RaceMenuLabels {
        var texts: [String: String] = [:]
        for key in RaceMenuLabels.english.keys {
            texts[key] = game.mapWorld.text(game.mapWorld.records?.menuTexts[key])
        }
        return RaceMenuLabels(texts: texts, genders: game.mapWorld.settingTexts(GenderText.self))
    }

    func raceMenuOptions(race: FormID, isFemale: Bool) -> RaceMenuOptions {
        guard
            let records = game.mapWorld.records,
            let record = records.playableRaces.first(where: { $0.formID == race })
        else { return .empty }
        let chargen = records.chargen
        var options = RaceMenuOptions.build(
            head: isFemale ? record.details.headData.female : record.details.headData.male,
            parts: { chargen.parts($0, race: race, isFemale: isFemale).map(\.formID) },
            color: { chargen.colors[$0.rawValue]?.color },
            presets: racePresets(race: race, isFemale: isFemale)
        )
        options.partTypes = records
            .chargenTypes[ChargenTypeKey(race: race, isFemale: isFemale)] ?? [:]
        return options
    }

    func racePresets(race: FormID, isFemale: Bool) -> [RacePreset] {
        guard let record = game.mapWorld.records?.playableRaces.first(where: { $0.formID == race })
        else {
            return []
        }
        let head = isFemale ? record.details.headData.female : record.details.headData.male
        return head.presets.compactMap { preset in
            guard let npc = identityRecords?.templates.actors[preset.rawValue]
            else { return nil }
            let name = npc.editorID ?? "\(preset)"
            return RacePreset(
                name: name,
                face: PlayerIdentityState(record: npc, details: npc.details, name: name).face
            )
        }
    }

    var identityRecords: ActorIdentityRecords? {
        game.menuRecords?.actorValueBaselines?.resolver
            .map(ActorIdentityRecords.init(resolver:))
    }

    /// The `Player` record's own identity, before the race menu changed it.
    var recordIdentity: PlayerIdentityState? {
        guard let player = game.mapWorld.records?.player else { return nil }
        return PlayerIdentityState(
            record: player, details: player.details,
            name: game.mapWorld.text(player.name) ?? "Prisoner"
        )
    }
}
