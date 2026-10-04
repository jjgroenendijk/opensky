// The records the title, race, and map menus read: the `Player` NPC_, the
// playable races, the map markers, the Tamriel map bounds, and the map GMSTs.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct MenuMapSettings: Equatable, Sendable {
    public var revealDistance: Float
    public var visibleDistance: Float
    public var discoveryExperience: Int

    /// Measured in the install: 1000, 12500, and 10.
    public static let vanilla = Self(
        revealDistance: 1000, visibleDistance: 12500, discoveryExperience: 10
    )

    public init(revealDistance: Float, visibleDistance: Float, discoveryExperience: Int) {
        self.revealDistance = revealDistance
        self.visibleDistance = visibleDistance
        self.discoveryExperience = discoveryExperience
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
            ))
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
    public let mapSettings: MenuMapSettings
    /// String GMSTs the menus show, such as `sNoFastTravelCombat`, by editor ID.
    public let menuTexts: [String: LString]

    public init(
        file: ESMFile, plugins: [(name: String, file: ESMFile)], settings: GameSettingStore
    ) {
        let localized = file.isLocalized
        let player = Self.records(in: file, of: "NPC_").first {
            $0.formID == Self.playerBase.rawValue
        }.flatMap { try? ActorBase(record: $0, localized: localized) }
        let races = Self.records(in: file, of: "RACE").compactMap {
            try? Race(record: $0, localized: localized)
        }.filter { $0.flags.contains(.playable) }
        let tamriel = Self.records(in: file, of: "WRLD").lazy.compactMap {
            try? Worldspace(record: $0, localized: localized)
        }.first { $0.editorID == Self.tamrielEditorID }
        self.player = player
        playableRaces = races.sorted { ($0.editorID ?? "") < ($1.editorID ?? "") }
        self.tamriel = tamriel
        markers = MapMarkerIndex(plugins: plugins)
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

    /// The direct record children of one top group; nested groups are skipped.
    private static func records(in file: ESMFile, of type: FourCC) -> [ESMRecord] {
        guard let top = file.topGroup(of: type), let children = try? top.children() else {
            return []
        }
        return children.compactMap {
            if case let .record(record) = $0, record.type == type, !record.isDeleted {
                return record
            }
            return nil
        }
    }
}
