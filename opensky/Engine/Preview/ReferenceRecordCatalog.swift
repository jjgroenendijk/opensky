// Load-order-wide browse rows for reference-record families.
// The app binds controls to this query model; plugin precedence, editor-ID
// extraction and sorting stay AppKit-free and deterministic.

import Foundation

nonisolated enum ReferenceRecordType: String, CaseIterable {
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

    var fourCC: FourCC {
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
        }
    }

    var title: String {
        switch self {
        case .keyword: "KYWD — Keywords"
        case .formList: "FLST — Form lists"
        case .location: "LCTN — Locations"
        case .locationReferenceType: "LCRT — Location reference types"
        case .encounterZone: "ECZN — Encounter zones"
        case .action: "AACT — Actions"
        case .collisionLayer: "COLL — Collision layers"
        case .defaultObjects: "DOBJ — Default objects"
        case .magicEffect: "MGEF — Magic effects"
        case .spell: "SPEL — Spells"
        case .scroll: "SCRL — Scrolls"
        case .enchantment: "ENCH — Enchantments"
        case .shout: "SHOU — Shouts"
        case .wordOfPower: "WOOP — Words of power"
        case .leveledSpell: "LVSP — Leveled spells"
        case .dualCastData: "DUAL — Dual cast data"
        case .equipSlot: "EQUP — Equip slots"
        }
    }
}

nonisolated struct ReferenceRecordCatalog {
    static let inspectedItemTypes: Set<FourCC> = [
        "MISC", "BOOK", "ALCH", "INGR", "WEAP", "AMMO", "ARMO"
    ]

    let pluginNames: [String]
    let index: RecordIndex
    private let itemsByType: [ReferenceRecordType: [PreviewItem]]

    init(index: RecordIndex, pluginNames: [String]) {
        self.index = index
        self.pluginNames = pluginNames
        var grouped: [ReferenceRecordType: [PreviewItem]] = [:]
        for type in ReferenceRecordType.allCases {
            grouped[type] = Self.items(type: type, index: index)
        }
        itemsByType = grouped
    }

    func items(for type: ReferenceRecordType, winningPlugin: String?) -> [PreviewItem] {
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

    static func editorID(in record: ESMRecord) -> String? {
        guard
            let field = try? record.fields().first(where: { $0.type == "EDID" }),
            field.data.last == 0
        else { return nil }
        return String(data: Data(field.data.dropLast()), encoding: .utf8)
    }
}
