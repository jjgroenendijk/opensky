// The records the title, race, and map menus read: the `Player` NPC_, the
// playable races, the map markers, the Tamriel map bounds, and the map GMSTs.
// The records are decoded the first time a menu reads them.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public struct MenuMapSettings: Equatable, Sendable {
    public var revealDistance: Float
    public var visibleDistance: Float
    /// `fFastTravelSpeedMult`. Skyrim.esm has no record of it, so the engine
    /// default of 1 applies unless a plugin adds one.
    public var fastTravelSpeedMultiplier: Float
    /// `fHUDCompassLocationMaxDist`: a known marker closer than this is on the compass.
    public var compassDistance: Float = 20000
    /// `iMapMarkerFadeStartDistance`: a compass marker fades out up to this distance.
    public var fadeStartDistance: Float = 10000

    /// Measured in the install: 1000 and 12500; the compass distances 20000 and 10000.
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
        compassDistance = number("fHUDCompassLocationMaxDist", vanilla.compassDistance)
        fadeStartDistance = number("iMapMarkerFadeStartDistance", vanilla.fadeStartDistance)
    }
}

nonisolated public struct MenuRecordData: Sendable {
    public static let playerBase = FormID(0x7)
    /// The menus read every setting that has this prefix, so `openskycli gaps` counts
    /// them as read.
    public static let statsPrefix = "fStats"
    /// The default object naming the PC help topic list.
    public static let helpManualTag = "HMPC"
    /// The Creations list without the Anniversary Edition upgrade; `HMAE` names the longer one.
    public static let installedContentTag = "HMCC"

    /// A string setting the fast-travel, race, or alchemy menus or the HUD show.
    public static func isMenuText(_ editorID: String) -> Bool {
        editorID.hasPrefix("sNoFastTravel") || editorID.hasPrefix("sRSM")
            || editorID == "sFastTravelConfirm" || editorID == "sFastTravelNoTravelHealthDamage"
            || editorID == "sOverEncumbered" || editorID == "sTESVDLC2DragonUnableToFlyMessage"
            || alchemyTexts.contains(editorID)
    }

    /// The alchemy lab's notices.
    public static let alchemyTexts: Set = [
        "sCreatedPotionNamePrefix", "sCreatedPoisonNamePrefix", "sPotionCreationFailed",
        "sCreated", "sDiscoveredEffects", "sDiscoveredIngredientEffectEating"
    ]

    /// The `Player` NPC_ and the playable races, decoded on first use.
    private struct Races: Sendable {
        let player: ActorBase?
        /// RACE records with the playable flag, sorted by editor ID.
        let playable: [Race]
    }

    /// The map markers and the WRLD records, decoded on first use.
    private struct Map: Sendable {
        let markers: MapMarkerIndex
        let worldspaces: [String: Worldspace]
        let worldspaceIDs: [String: ResolvedFormID]
    }

    /// The System page's lists and the title light, decoded on first use.
    private struct Content: Sendable {
        let installedContent: ResolvedFormID?
        let helpManual: ResolvedFormID?
    }

    private let races: FirstUseValue<Races>
    private let map: FirstUseValue<Map>
    private let chargenRecords: FirstUseValue<ChargenRecords>
    private let content: FirstUseValue<Content>
    private var chargenTypeTable: FirstUseValue<[ChargenTypeKey: [Int: Int]]>?

    public let mapSettings: MenuMapSettings
    /// String GMSTs the menus show, such as `sNoFastTravelCombat` and `sRSMBody`, by editor ID.
    public let menuTexts: [String: LString]
    /// The `fStats` float GMSTs that shape the skills menu's perk sky.
    public let statsSettings: [String: Float]

    public var player: ActorBase? {
        races.value.player
    }

    /// RACE records with the playable flag, sorted by editor ID.
    public var playableRaces: [Race] {
        races.value.playable
    }

    public var markers: MapMarkerIndex {
        map.value.markers
    }

    /// Every WRLD record by editor ID.
    public var worldspaces: [String: Worldspace] {
        map.value.worldspaces
    }

    /// Each WRLD's plugin-relative identity, the key map markers are grouped by.
    public var worldspaceIDs: [String: ResolvedFormID] {
        map.value.worldspaceIDs
    }

    /// Head parts and colours for the race menu.
    public var chargen: ChargenRecords {
        chargenRecords.value
    }

    /// The FLST of Creation messages the System page's Installed Content lists.
    public var installedContent: ResolvedFormID? {
        content.value.installedContent
    }

    /// The FLST of help topics the System page's Help lists: the DOBJ `HMPC` default object.
    public var helpManual: ResolvedFormID? {
        content.value.helpManual
    }

    /// The highest type each race and sex's chargen TRI holds, by `NAMA` index. Empty
    /// until `readChargenTypes(with:)` names how to read them.
    public var chargenTypes: [ChargenTypeKey: [Int: Int]] {
        chargenTypeTable?.value ?? [:]
    }

    /// True once a menu read the records of `part`, for tests of the first-use decode.
    func isDecoded(_ part: DecodedPart) -> Bool {
        switch part {
        case .races: races.isBuilt
        case .map: map.isBuilt
        case .chargen: chargenRecords.isBuilt
        case .content: content.isBuilt
        }
    }

    enum DecodedPart: Sendable {
        case races, map, chargen, content
    }

    /// Every plugin's records; a later plugin's override wins. Only the settings are read
    /// here; each part of the records is decoded the first time a menu reads it.
    public init(loadOrder: LoadOrderPlugins, settings: GameSettingStore) {
        races = FirstUseValue { Self.races(loadOrder) }
        map = FirstUseValue { Self.map(loadOrder) }
        chargenRecords = FirstUseValue {
            var skipped = SkippedRecords()
            return ChargenRecords(loadOrder: loadOrder, skipped: &skipped)
        }
        content = FirstUseValue {
            let defaultObjects = DefaultObjectStore(plugins: loadOrder.files)
            return Content(
                installedContent: defaultObjects.object(tag: Self.installedContentTag),
                helpManual: defaultObjects.object(tag: Self.helpManualTag)
            )
        }
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

    /// Reads the chargen types with `read` the first time the race menu asks for them.
    public mutating func readChargenTypes(
        with read: @escaping @Sendable (MenuRecordData) -> [ChargenTypeKey: [Int: Int]]
    ) {
        let records = self
        chargenTypeTable = FirstUseValue { read(records) }
    }

    private static func races(_ loadOrder: LoadOrderPlugins) -> Races {
        var skipped = SkippedRecords()
        let player = loadOrder.indexRecords(of: "NPC_", skipped: &skipped) { record, localized in
            FormID(record.formID) == Self.playerBase
                ? try ActorBase(record: record, localized: localized) : nil
        }[Self.playerBase.rawValue]
        let races = loadOrder.decodeRecords(of: "RACE", skipped: &skipped) {
            try Race(record: $0, localized: $1)
        }.filter { $0.flags.contains(.playable) }
        return Races(
            player: player,
            playable: races.sorted { ($0.editorID ?? "") < ($1.editorID ?? "") }
        )
    }

    private static func map(_ loadOrder: LoadOrderPlugins) -> Map {
        var skipped = SkippedRecords()
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
        return Map(
            markers: MapMarkerIndex(plugins: loadOrder.files),
            worldspaces: byName,
            worldspaceIDs: ids
        )
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
