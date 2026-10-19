// The records the title, race, and map menus read: the `Player` NPC_, the
// playable races, the map markers, the Tamriel map bounds, and the map GMSTs.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct MenuMapSettings: Equatable, Sendable {
    public var revealDistance: Float
    public var visibleDistance: Float
    public var discoveryExperience: Int
    /// `fFastTravelSpeedMult`. Skyrim.esm has no record of it, so the engine
    /// default of 1 applies unless a plugin adds one.
    public var fastTravelSpeedMultiplier: Float

    /// Measured in the install: 1000, 12500, and 10.
    public static let vanilla = Self(
        revealDistance: 1000, visibleDistance: 12500, discoveryExperience: 10
    )

    public init(
        revealDistance: Float, visibleDistance: Float, discoveryExperience: Int,
        fastTravelSpeedMultiplier: Float = 1
    ) {
        self.revealDistance = revealDistance
        self.visibleDistance = visibleDistance
        self.discoveryExperience = discoveryExperience
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
            discoveryExperience: Int(number(
                "iXPRewardDiscoverMapMarker", Float(vanilla.discoveryExperience)
            )),
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

nonisolated extension MenuRecordData {
    /// The worldspace whose map a player in `editorID` sees. WhiterunWorld sets the
    /// `PNAM` map flag, so it shows Tamriel's map.
    public func mapWorldspace(of editorID: String) -> Worldspace? {
        guard let world = worldspaces[editorID] else { return nil }
        let byID = Dictionary(worldspaces.values.map { ($0.formID.rawValue, $0) }) { _, new in new }
        return world.source(of: .useMapData, in: byID)
    }
}
