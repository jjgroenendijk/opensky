// Load-order-wide browse rows for reference-record families.
// The app binds controls to this query model; plugin precedence, editor-ID
// extraction and sorting stay AppKit-free and deterministic.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public enum ReferenceRecordType: String, CaseIterable, Sendable {
    case keyword = "KYWD"
    case formList = "FLST"
    case location = "LCTN"
    case locationReferenceType = "LCRT"
    case encounterZone = "ECZN"
    case action = "AACT"
    case collisionLayer = "COLL"
    case defaultObjects = "DOBJ"
    case magicEffect = "MGEF"
    case spell = "SPEL"
    case scroll = "SCRL"
    case enchantment = "ENCH"
    case shout = "SHOU"
    case wordOfPower = "WOOP"
    case leveledSpell = "LVSP"
    case dualCastData = "DUAL"
    case equipSlot = "EQUP"
    case actorValueInformation = "AVIF"
    case perk = "PERK"
    case faction = "FACT"
    case relationship = "RELA"
    case associationType = "ASTP"
    case constructibleObject = "COBJ"
    case key = "KEYM"
    case soulGem = "SLGM"
    case apparatus = "APPA"
    case flora = "FLOR"
    case talkingActivator = "TACT"
    case artObject = "ARTO"
    case cameraShot = "CAMS"
    case cameraPath = "CPTH"
    case combatStyle = "CSTY"
    case message = "MESG"
    case loadScreen = "LSCR"

    public var fourCC: FourCC {
        switch self {
        case .keyword: "KYWD"
        case .formList: "FLST"
        case .location: "LCTN"
        case .locationReferenceType: "LCRT"
        case .encounterZone: "ECZN"
        case .action: "AACT"
        case .collisionLayer: "COLL"
        case .defaultObjects: "DOBJ"
        case .magicEffect: "MGEF"
        case .spell: "SPEL"
        case .scroll: "SCRL"
        case .enchantment: "ENCH"
        case .shout: "SHOU"
        case .wordOfPower: "WOOP"
        case .leveledSpell: "LVSP"
        case .dualCastData: "DUAL"
        case .equipSlot: "EQUP"
        case .actorValueInformation: "AVIF"
        case .perk: "PERK"
        case .faction: "FACT"
        case .relationship: "RELA"
        case .associationType: "ASTP"
        case .constructibleObject: "COBJ"
        case .key: "KEYM"
        case .soulGem: "SLGM"
        case .apparatus: "APPA"
        case .flora: "FLOR"
        case .talkingActivator: "TACT"
        case .artObject: "ARTO"
        case .cameraShot: "CAMS"
        case .cameraPath: "CPTH"
        case .combatStyle: "CSTY"
        case .message: "MESG"
        case .loadScreen: "LSCR"
        }
    }
}

nonisolated public struct ReferenceRecordCatalog: Sendable {
    public static let inspectedItemTypes: Set<FourCC> = [
        "MISC", "BOOK", "ALCH", "INGR", "WEAP", "AMMO", "ARMO"
    ]

    /// Every type the browse list offers, for the index the app builds.
    public static let browsedTypes = Set(ReferenceRecordType.allCases.map(\.fourCC))

    private let itemsByType: [ReferenceRecordType: [PreviewItem]]

    public init(index: RecordIndex) {
        var grouped: [ReferenceRecordType: [PreviewItem]] = [:]
        for type in ReferenceRecordType.allCases {
            grouped[type] = Self.items(type: type, index: index)
        }
        itemsByType = grouped
    }

    public func items(for type: ReferenceRecordType, winningPlugin: String?) -> [PreviewItem] {
        let items = itemsByType[type, default: []]
        guard let winningPlugin else { return items }
        return items.filter { item in
            guard case let .record(record) = item.selection else { return false }
            return record.sourcePlugin.caseInsensitiveCompare(winningPlugin) == .orderedSame
        }
    }

    private static func items(type: ReferenceRecordType, index: RecordIndex) -> [PreviewItem] {
        index.records.compactMap { id, indexed -> PreviewItem? in
            guard indexed.record.type == type.fourCC else { return nil }
            let editorID = editorID(in: indexed.record) ?? "[NO EDID]"
            let display = "\(editorID) — \(indexed.sourcePlugin) — \(id)"
            return PreviewItem(
                display: display,
                searchKey: display.lowercased(),
                selection: .record(PreviewRecord(
                    record: indexed.record,
                    sourcePlugin: indexed.sourcePlugin,
                    localized: indexed.localized,
                    resolvedID: id
                ))
            )
        }
        .sorted { $0.display.localizedCaseInsensitiveCompare($1.display) == .orderedAscending }
    }

    public static func editorID(in record: ESMRecord) -> String? {
        guard
            let field = try? record.fields().first(where: { $0.type == "EDID" }),
            field.data.last == 0
        else { return nil }
        return String(data: Data(field.data.dropLast()), encoding: .utf8)
    }
}
