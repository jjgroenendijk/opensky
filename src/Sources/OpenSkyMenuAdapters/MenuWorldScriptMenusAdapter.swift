import Foundation
import OpenSkyActorsInterface
import OpenSkyAgentControl
import OpenSkyAudio
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyLaunch
import OpenSkyLoading
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyMenusInterface
import OpenSkyPlayer
import OpenSkyProgressionInterface
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkySaveInterface
import OpenSkyScriptingInterface
public import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MenuWorldScriptMenusAdapter` reads from the session.
@MainActor
public protocol MenuWorldScriptMenusHost: AnyObject, SendableMetatype {
    var containerMenu: any ContainerMenuPort { get }
    var hud: any HUDPort { get }
    var magic: any MagicPort { get }
    var mapMenu: any MapMenuPort { get }
    var mapWorld: any MapWorldPort { get }
    var menuScreens: any MenuScreensPort { get }
    var raceMenu: any RaceMenuPort { get }
    var scripts: any ScriptPort { get }
    var streamer: any CellStreamerPort { get }
    var menuRecords: (any MenuRecordsPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

/// Part of `MenuWorldAdapter`, over its own narrow host.
public struct MenuWorldScriptMenusAdapter {
    public let game: any MenuWorldScriptMenusHost
    public let state: MenuPartState
    public let skillsRace: MenuWorldSkillsRaceAdapter
    public let teleports: MenuWorldTeleportsAdapter
}

extension MenuWorldScriptMenusAdapter {
    public func showRaceMenu(limited: Bool) {
        game.raceMenu.open(limited: limited)
    }

    public func fastTravel(to marker: ReferenceKey) -> Bool {
        guard game.mapMenu.select(key: marker) else { return false }
        game.mapMenu.travelToSelected()
        return true
    }

    public func setFastTravelEnabled(_ enabled: Bool) {
        game.mapMenu.fastTravelEnabled = enabled
    }

    public func setHUDCartMode(_ enabled: Bool) {
        game.hud.setCartMode(enabled)
    }

    var isFastTravelEnabled: Bool {
        game.mapMenu.fastTravelEnabled
    }

    public func canFastTravel(to marker: ReferenceKey) -> Bool {
        game.mapMenu.canTravel(to: marker)
    }

    public func addToMap(_ marker: ReferenceKey, allowFastTravel: Bool) {
        game.mapMenu.addToMap(marker, allowFastTravel: allowFastTravel)
    }

    public func isMapMarkerVisible(_ marker: ReferenceKey) -> Bool {
        game.mapMenu.isVisible(marker)
    }

    public func race(of actor: ReferenceKey) -> FormID? {
        if actor == .player {
            return skillsRace.playerIdentity?.race
        }
        guard
            let base = game.scripts.bridge?.baseObject(of: actor),
            let records = skillsRace.identityRecords
        else { return nil }
        let roll = game.worldState.leveledRoll(
            of: actor,
            base: base,
            with: records.templates.leveling
        )
        return records.race(ofBase: base, roll: roll)
    }

    /// Only the player changes race: an NPC's body is built from its record.
    @discardableResult
    public func setRace(of actor: ReferenceKey, to race: FormID?) -> Bool {
        guard actor == .player, var identity = skillsRace.playerIdentity else { return false }
        let original = state.originalPlayerRace ?? identity.race
        guard let wanted = race ?? state.originalPlayerRace else { return true }
        state.originalPlayerRace = wanted == original ? nil : original
        identity.race = wanted
        skillsRace.applyPlayerIdentity(identity)
        game.scripts.runtime?.queueRaceSwitchComplete(actor: .player)
        return true
    }

    public func sex(ofBase base: FormID) -> Int? {
        let isFemale = base == MenuRecordData.playerBase
            ? skillsRace.playerIdentity?.isFemale : skillsRace.identityRecords?
            .isFemale(ofBase: base)
        return isFemale.map { $0 ? 1 : 0 }
    }

    public func race(ofBase base: FormID) -> FormID? {
        base == MenuRecordData.playerBase
            ? skillsRace.playerIdentity?.race : skillsRace.identityRecords?.race(ofBase: base)
    }

    public func recordFlags(ofBase base: FormID) -> ActorBase.Flags? {
        skillsRace.identityRecords?.templates.actors[base.rawValue]?.flags
    }

    public func leveledBase(of actor: ReferenceKey, base: FormID) -> FormID? {
        guard let templates = game.menuRecords?.actorValueBaselines?.resolver?.templates
        else { return base }
        let roll = game.worldState.leveledRoll(of: actor, base: base, with: templates.leveling)
        return templates.rolling(roll).leveledBase(of: base)
    }

    public func recordShouts(ofBase base: FormID) -> [ReferenceKey] {
        guard
            let spells = skillsRace.identityRecords?.templates.actors[base.rawValue]?.spells,
            let bridge = game.scripts.bridge
        else { return [] }
        let shouts = game.magic.shouts
        return spells.compactMap(bridge.referenceKey(forFormID:)).filter { shouts[$0] != nil }
    }

    public func voiceType(ofBase base: FormID) -> FormID? {
        skillsRace.identityRecords?.voiceType(ofBase: base)
    }

    public func giftFilter(ofBase base: FormID) -> FormID? {
        skillsRace.identityRecords?.templates.actors[base.rawValue]?.details.giftFilter
    }

    public func name(of form: FormID) -> String? {
        if form == MenuRecordData.playerBase {
            return skillsRace.playerIdentity?.name
        }
        return game.mapWorld.text(skillsRace.identityRecords?.name(of: form))
    }

    /// Only `Skyrim.esm` references, because the lookup outside the loaded cells
    /// reads that file.
    public func movePlayer(to target: ReferenceKey) {
        guard case let .plugin(name, objectID) = target, name == "skyrim.esm" else {
            game.hud.showNotification("MoveTo: \(target) is not in Skyrim.esm")
            return
        }
        // A move out of the loaded cells loads a new area, so the game shows a screen.
        if game.streamer.referenceEntry(key: target) == nil {
            state.coverNextTeleport = true
        }
        unsafe teleports.teleportPlayer(
            .reference(String(format: "0x%06X", objectID)),
            openingRaceMenu: false
        )
    }

    public func openInventory(of actor: ReferenceKey) {
        game.containerMenu.openInventory(of: actor)
    }

    public func showTrainingMenu(trainer: ReferenceKey) {
        game.menuScreens.training.open(trainer: trainer)
    }

    public func showGiftMenu(
        actor: ReferenceKey, giving: Bool, filter: [ReferenceKey?]?, showsStolenItems: Bool
    ) {
        let request = GiftMenuRequest(
            giving: giving, filter: filter.map { Set($0.compactMap(\.self)) },
            showsStolenItems: showsStolenItems
        )
        game.menuScreens.gift.open(actor: actor, request: request)
    }
}
