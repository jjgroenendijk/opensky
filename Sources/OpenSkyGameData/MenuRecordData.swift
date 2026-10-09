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
    public static let tamrielEditorID = "Tamriel"

    public let player: ActorBase?
    /// RACE records with the playable flag, sorted by editor ID.
    public let playableRaces: [Race]
    public let markers: MapMarkerIndex
    public let tamriel: Worldspace?
    /// Editor IDs of the master's WRLD records, for the marker inspector.
    public let worldspaceEditorIDs: [UInt32: String]
    public let mapSettings: MenuMapSettings
    /// String GMSTs the menus show, such as `sNoFastTravelCombat`, by editor ID.
    public let menuTexts: [String: LString]

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
        let tamriel = worldspaces.first { $0.editorID == Self.tamrielEditorID }
        worldspaceEditorIDs = worldspaces.reduce(into: [:]) { names, space in
            names[space.formID.rawValue] = space.editorID
        }
        self.player = player
        playableRaces = races.sorted { ($0.editorID ?? "") < ($1.editorID ?? "") }
        self.tamriel = tamriel
        markers = MapMarkerIndex(plugins: loadOrder.files)
        mapSettings = MenuMapSettings(store: settings)
        menuTexts = settings.values.values.reduce(into: [:]) { texts, resolved in
            let name = resolved.setting.editorID
            guard
                name.hasPrefix("sNoFastTravel") || name == "sFastTravelConfirm",
                case let .string(text) = resolved.setting.value
            else { return }
            texts[name] = text
        }
    }
}
