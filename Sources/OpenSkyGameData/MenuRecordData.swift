// The records the title, race, and map menus read: the `Player` NPC_, the
// playable races, the map markers, the Tamriel map bounds, and the map GMSTs.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct MenuMapSettings: Equatable, Sendable {
    public var revealDistance: Float
    public var visibleDistance: Float
    /// `fFastTravelSpeedMult`. Skyrim.esm has no record of it, so the engine
    /// default of 1 applies unless a plugin adds one.
    public var fastTravelSpeedMultiplier: Float

    /// Measured in the install: 1000 and 12500.
    public static let vanilla = Self(revealDistance: 1000, visibleDistance: 12500)

    public init(
        revealDistance: Float, visibleDistance: Float, fastTravelSpeedMultiplier: Float = 1
    ) {
        self.revealDistance = revealDistance
        self.visibleDistance = visibleDistance
        self.fastTravelSpeedMultiplier = fastTravelSpeedMultiplier
    }

    public init(store: GameSettingStore) {
        func number(_ name: String, _ fallback: Float) -> Float {
            switch store.setting(editorID: name)?.setting.value {
            case let .integer(value)?: Float(value)
            case let .float(value)?: value
            default: fallback
            }
        }
        let vanilla = Self.vanilla
        self.init(
            revealDistance: number("iMapMarkerRevealDistance", vanilla.revealDistance),
            visibleDistance: number("iMapMarkerVisibleDistance", vanilla.visibleDistance),
            fastTravelSpeedMultiplier: number(
                "fFastTravelSpeedMult", vanilla.fastTravelSpeedMultiplier
            )
        )
    }
}

nonisolated public struct MenuRecordData: Sendable {
    public static let playerBase = FormID(0x7)
    /// The menus read every setting that has this prefix, so `openskycli gaps` counts
    /// them as read.
    public static let statsPrefix = "fStats"
    /// The default object naming the PC help topic list.
    public static let helpManualTag = "HMPC"

    /// A string setting the fast-travel, race, or alchemy menus or the HUD show.
    public static func isMenuText(_ editorID: String) -> Bool {
        editorID.hasPrefix("sNoFastTravel") || editorID.hasPrefix("sRSM")
            || editorID == "sFastTravelConfirm" || editorID == "sOverEncumbered"
            || alchemyTexts.contains(editorID)
    }

    /// The alchemy lab's notices.
    public static let alchemyTexts: Set = [
        "sCreatedPotionNamePrefix", "sCreatedPoisonNamePrefix", "sPotionCreationFailed"
    ]

    public let player: ActorBase?
    /// RACE records with the playable flag, sorted by editor ID.
    public let playableRaces: [Race]
    public let markers: MapMarkerIndex
    /// Every WRLD record by editor ID.
    public let worldspaces: [String: Worldspace]
    /// Each WRLD's plugin-relative identity, the key map markers are grouped by.
    public let worldspaceIDs: [String: ResolvedFormID]
    public let mapSettings: MenuMapSettings
    /// String GMSTs the menus show, such as `sNoFastTravelCombat` and `sRSMBody`, by editor ID.
    public let menuTexts: [String: LString]
    /// Head parts and colours for the race menu.
    public let chargen: ChargenRecords
    /// The `fStats` float GMSTs that shape the skills menu's perk sky.
    public let statsSettings: [String: Float]
    /// The active plugins in load order, for the System page's Installed Content.
    public let installedPlugins: [InstalledPlugin]
    /// The FLST of help topics the System page's Help lists: the DOBJ `HMPC` default object.
    public let helpManual: ResolvedFormID?
    /// The light the main menu's logo and smoke are drawn under.
    public let mainMenuLighting: MainMenuCellLighting?
    /// The highest type each race and sex's chargen TRI holds, by `NAMA` index. Filled
    /// from the install after the records load.
    public var chargenTypes: [ChargenTypeKey: [Int: Int]] = [:]

    /// Every plugin's records; a later plugin's override wins.
    public init(loadOrder: LoadOrderPlugins, settings: GameSettingStore) {
        var skipped = SkippedRecords()
        let player = loadOrder.indexRecords(of: "NPC_", skipped: &skipped) { record, localized in
            FormID(record.formID) == Self.playerBase
                ? try ActorBase(record: record, localized: localized) : nil
        }[Self.playerBase.rawValue]
        let races = loadOrder.decodeRecords(of: "RACE", skipped: &skipped) {
            try Race(record: $0, localized: $1)
        }.filter { $0.flags.contains(.playable) }
        let worldspaces = loadOrder.decodeRecords(of: "WRLD", skipped: &skipped) {
            try Worldspace(record: $0, localized: $1)
        }
        var byName: [String: Worldspace] = [:]
        var ids: [String: ResolvedFormID] = [:]
        for world in worldspaces {
            guard let name = world.editorID else { continue }
            byName[name] = world
            ids[name] = loadOrder.space.resolve(world.formID)
        }
        self.worldspaces = byName
        worldspaceIDs = ids
        chargen = ChargenRecords(loadOrder: loadOrder, skipped: &skipped)
        self.player = player
        playableRaces = races.sorted { ($0.editorID ?? "") < ($1.editorID ?? "") }
        markers = MapMarkerIndex(plugins: loadOrder.files)
        installedPlugins = loadOrder.plugins.map { InstalledPlugin(name: $0.name, file: $0.file) }
        let defaultObjects = DefaultObjectStore(plugins: loadOrder.files)
        helpManual = defaultObjects.object(tag: Self.helpManualTag)
        mainMenuLighting = MainMenuCellLighting(
            loadOrder: loadOrder, defaultObjects: defaultObjects
        )
        mapSettings = MenuMapSettings(store: settings)
        menuTexts = settings.values.values.reduce(into: [:]) { texts, resolved in
            let name = resolved.setting.editorID
            guard
                Self.isMenuText(name),
                case let .string(text) = resolved.setting.value
            else { return }
            texts[name] = text
        }
        statsSettings = settings.values.values.reduce(into: [:]) { values, resolved in
            guard
                resolved.setting.editorID.hasPrefix(Self.statsPrefix),
                case let .float(value) = resolved.setting.value
            else { return }
            values[resolved.setting.editorID] = value
        }
    }
}

/// One race and sex, the unit a chargen TRI belongs to.
nonisolated public struct ChargenTypeKey: Hashable, Sendable {
    public let race: FormID
    public let isFemale: Bool

    public init(race: FormID, isFemale: Bool) {
        self.race = race
        self.isFemale = isFemale
    }
}

nonisolated extension MenuRecordData {
    /// The chargen TRI path of each race and sex's default face part.
    public var chargenTRIPaths: [ChargenTypeKey: String] {
        let parts = Dictionary(chargen.headParts.map { ($0.formID, $0) }) { first, _ in first }
        var paths: [ChargenTypeKey: String] = [:]
        for race in playableRaces {
            for (isFemale, list) in [(false, race.maleHeadParts), (true, race.femaleHeadParts)] {
                let face = list.compactMap { parts[$0] }.first { $0.partType == .face }
                if let path = face?.morphPaths.first(where: { $0.kind == .chargen })?.path {
                    paths[ChargenTypeKey(race: race.formID, isFemale: isFemale)] = path
                }
            }
        }
        return paths
    }
}

nonisolated extension MenuRecordData {
    /// The worldspace whose map a player in `editorID` sees. WhiterunWorld sets the
    /// `PNAM` map flag, so it shows Tamriel's map.
    public func mapWorldspace(of editorID: String) -> Worldspace? {
        guard let world = worldspaces[editorID] else { return nil }
        let byID = Dictionary(worldspaces.values.map { ($0.formID.rawValue, $0) }) { _, new in new }
        return world.source(of: .useMapData, in: byID)
    }
}
