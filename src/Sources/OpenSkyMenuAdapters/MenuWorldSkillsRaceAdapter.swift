public import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAudio
public import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventory
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagic
public import OpenSkyMenus
public import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgression
public import OpenSkyProgressionInterface
public import OpenSkyRenderCore
public import OpenSkyRendering
import OpenSkySave
import OpenSkySaveInterface
import OpenSkyScripting
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
public import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldSkillsRaceAdapter` reads from the session.
@MainActor
public protocol MenuWorldSkillsRaceHost: MenuInputConsumer {
    var audio: any AudioPort { get }
    var gameSession: (any GameSessionPort)? { get }
    var mapWorld: any MapWorldPort { get }
    var player: any PlayerPort { get }
    var playerBeastForm: PlayerBeastForm { get }
    var progression: any ProgressionPort { get }
    var renderer: (any RendererPort)? { get }
    var scripts: any ScriptPort { get }
    var swfMovies: any SWFMovieSourcePort { get }
    var worldData: WorldDataStores? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MenuWorldAdapter`, over its own narrow host.
public struct MenuWorldSkillsRaceAdapter {
    public unowned let owner: MenuWorldAdapter
    public unowned let game: any MenuWorldSkillsRaceHost
}

extension MenuWorldSkillsRaceAdapter {
    /// Nil until leveling is wired, so the menu does not open on an empty card.
    public var skillsMenuSource: (any SkillsMenuSource)? {
        game.progression.leveling == nil ? nil : game.progression
    }

    public var menuInputConsumer: (any MenuInputConsumer)? {
        game
    }

    public var isPlayerInBeastForm: Bool {
        game.playerBeastForm.isBeast
    }

    public func playLevelUpMusic() {
        game.audio.musicDirector?.playSpecialMusic(.levelUp)
    }

    public var skillsMenuTexts: GameSettingTexts<SkillsMenuText> {
        game.mapWorld.settingTexts()
    }

    public var perkSkySource: PerkSkySource? {
        if owner.perkSky == nil, let files = game.worldData?.scriptFileSystem {
            owner.perkSky = PerkSkySource(fileSystem: files)
        }
        return owner.perkSky
    }

    public var perkSkySettings: PerkSkySettings {
        let values = owner.records?.statsSettings ?? [:]
        return PerkSkySettings { values[$0] }
    }

    public var renderer: (any RendererPort)? {
        game.renderer
    }

    public var gameFiles: (any GameFileSource)? {
        game.swfMovies.fileSystem
    }

    public var viewCamera: FreeFlyCamera? {
        game.gameSession?.freeFlyCamera
    }

    public var uiScene: UIScene {
        get { game.gameSession?.uiScene ?? .empty }
        nonmutating set { game.gameSession?.uiScene = newValue }
    }

    public var playerIdentity: PlayerIdentityState? {
        game.worldState.component(PlayerIdentityState.self, for: .player) ?? owner.recordIdentity
    }

    public var playableRaces: [RaceChoice] {
        (owner.records?.playableRaces ?? []).map {
            RaceChoice(
                formID: $0.formID,
                name: game.mapWorld.text($0.name) ?? $0.editorID ?? "\($0.formID)",
                description: game.mapWorld.text($0.details.description, kind: .dlstrings) ?? ""
            )
        }
    }

    public var raceMenuLabels: RaceMenuLabels {
        var texts: [String: String] = [:]
        for key in RaceMenuLabels.english.keys {
            texts[key] = game.mapWorld.text(owner.records?.menuTexts[key])
        }
        return RaceMenuLabels(texts: texts, genders: game.mapWorld.settingTexts(GenderText.self))
    }

    public func raceMenuOptions(race: FormID, isFemale: Bool) -> RaceMenuOptions {
        guard
            let records = owner.records,
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

    public func applyPlayerIdentity(_ identity: PlayerIdentityState) {
        game.worldState.set(identity, for: .player)
        game.player.refreshBody()
    }

    public func racePresets(race: FormID, isFemale: Bool) -> [RacePreset] {
        guard let record = owner.records?.playableRaces.first(where: { $0.formID == race }) else {
            return []
        }
        let head = isFemale ? record.details.headData.female : record.details.headData.male
        return head.presets.compactMap { preset in
            guard let npc = owner.scriptMenus.identityRecords?.templates.actors[preset.rawValue]
            else { return nil }
            let name = npc.editorID ?? "\(preset)"
            return RacePreset(
                name: name,
                face: PlayerIdentityState(record: npc, details: npc.details, name: name).face
            )
        }
    }

    public func raceMenuClosed() {
        game.scripts.runtime?.queueRaceSwitchComplete(actor: .player)
    }
}
