// Read-only index of every carryable base record in one plugin, behind one
// unified view. The inventory runtime (#176) resolves an item FormID through
// here instead of knowing which of the seven record families it belongs to.
//
// Naming and shape follow the existing immutable stores (`WeatherStore`,
// `SoundRecordStore`): build once from an `ESMFile`, expose lookups, never
// mutate.
//
// Containers are indexed separately from items. A CONT is not carryable — it
// has no gold value and no weight — but the inventory runtime still has to
// read a container's starting contents, so `container(_:)` sits alongside
// `definition(_:)` rather than being forced into the same view.
//
// Stackability, v1: every item stacks by base FormID, which is what
// `ItemDefinition.stackKey` returns. That is correct only while no
// per-instance data exists. Tempering, enchanting, charge level and item
// health all make two instances of the same base FormID distinct, so the key
// grows into a compound one when the milestone that introduces per-instance
// data lands; see docs/formats/records.md.
//
// Scope: single-plugin, raw-FormID keyed, matching the convention the actor
// resolution indexes already use. Cross-plugin override resolution is a
// separate concern (`GameSettingStore` does it for GMST) and is not needed
// until the inventory runtime reads more than Skyrim.esm.

import Foundation

/// One carryable base record, reduced to what inventory needs from all of
/// them. The `family` tag says which record type it came from, so a consumer
/// that needs the full decode can go back to the typed record.
nonisolated struct ItemDefinition: Equatable {
    /// Which record family the definition came from.
    enum Family: String, Equatable, CaseIterable {
        case armor = "ARMO"
        case ammunition = "AMMO"
        case book = "BOOK"
        case ingestible = "ALCH"
        case ingredient = "INGR"
        case miscellaneous = "MISC"
        case weapon = "WEAP"

        /// The top group this family lives in. `FourCC` only builds from a
        /// string literal, so the mapping is spelled out rather than derived
        /// from `rawValue`.
        var recordType: FourCC {
            switch self {
            case .armor: "ARMO"
            case .ammunition: "AMMO"
            case .book: "BOOK"
            case .ingestible: "ALCH"
            case .ingredient: "INGR"
            case .miscellaneous: "MISC"
            case .weapon: "WEAP"
            }
        }
    }

    let formID: FormID
    let family: Family
    let editorID: String?
    /// FULL — display name. Nil on records that never surface in a menu.
    let name: LString?
    /// Gold value before enchantment adjustments.
    let value: Int32
    /// Carry weight.
    let weight: Float
    /// KYWD links (vendor category, material, weapon type).
    let keywords: [FormID]

    /// v1 stacking key: the base FormID. See the file header for why this is
    /// provisional.
    var stackKey: UInt32 {
        formID.rawValue
    }
}

nonisolated final class ItemDefinitionStore {
    /// Carryable item definitions, keyed by raw FormID.
    let definitions: [UInt32: ItemDefinition]
    /// CONT decodes, keyed by raw FormID.
    let containers: [UInt32: Container]

    /// Records that failed to decode, by family — surfaced so the real-data
    /// sweep can assert zero rather than silently indexing fewer items.
    let skippedCounts: [ItemDefinition.Family: Int]

    init(file: ESMFile) {
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        var definitions: [UInt32: ItemDefinition] = [:]
        var skipped: [ItemDefinition.Family: Int] = [:]
        for family in ItemDefinition.Family.allCases {
            var familySkips = 0
            for record in Self.records(of: family.recordType, in: file) {
                guard
                    let definition = Self.definition(
                        record: record, family: family, localized: localized
                    )
                else {
                    familySkips += 1
                    continue
                }
                definitions[definition.formID.rawValue] = definition
            }
            skipped[family] = familySkips
        }
        self.definitions = definitions
        skippedCounts = skipped
        containers = Self.records(of: "CONT", in: file)
            .compactMap { try? Container(record: $0, localized: localized) }
            .reduce(into: [:]) { $0[$1.formID.rawValue] = $1 }
    }

    func definition(_ id: FormID) -> ItemDefinition? {
        definitions[id.rawValue]
    }

    func container(_ id: FormID) -> Container? {
        containers[id.rawValue]
    }

    /// Every definition of one family, in FormID order — a stable listing for
    /// the record dump and the sweep test.
    func definitions(of family: ItemDefinition.Family) -> [ItemDefinition] {
        definitions.values
            .filter { $0.family == family }
            .sorted { $0.formID.rawValue < $1.formID.rawValue }
    }

    /// Decodes one record into the unified view. Returns nil when the typed
    /// decode throws, which the caller counts as a skip.
    private static func definition(
        record: ESMRecord,
        family: ItemDefinition.Family,
        localized: Bool
    ) -> ItemDefinition? {
        switch family {
        case .armor:
            (try? Armor(record: record, localized: localized)).map(view)
        case .ammunition:
            (try? Ammunition(record: record, localized: localized)).map(view)
        case .book:
            (try? Book(record: record, localized: localized)).map(view)
        case .ingestible:
            (try? Ingestible(record: record, localized: localized)).map(view)
        case .ingredient:
            (try? Ingredient(record: record, localized: localized)).map(view)
        case .miscellaneous:
            (try? MiscItem(record: record, localized: localized)).map(view)
        case .weapon:
            (try? Weapon(record: record, localized: localized)).map(view)
        }
    }

    private static func records(of type: FourCC, in file: ESMFile) -> [ESMRecord] {
        guard
            let group = file.topGroup(of: type),
            let children = try? group.children()
        else { return [] }
        return children.compactMap { child in
            guard case let .record(record) = child, record.type == type else { return nil }
            return record.isDeleted ? nil : record
        }
    }
}

/// Per-family projections into `ItemDefinition`. Free functions in one
/// extension rather than an `ItemViewConvertible` protocol: the record structs
/// are plain decoders and none of them should grow a store-shaped conformance.
nonisolated extension ItemDefinitionStore {
    fileprivate static func view(_ armor: Armor) -> ItemDefinition {
        ItemDefinition(
            formID: armor.formID,
            family: .armor,
            editorID: armor.editorID,
            name: armor.name,
            value: armor.itemValue.value,
            weight: armor.itemValue.weight,
            keywords: armor.keywords.keywords
        )
    }

    fileprivate static func view(_ ammunition: Ammunition) -> ItemDefinition {
        view(ammunition.formID, .ammunition, ammunition.fields, ammunition.itemValue)
    }

    fileprivate static func view(_ book: Book) -> ItemDefinition {
        view(book.formID, .book, book.fields, book.itemValue)
    }

    fileprivate static func view(_ ingestible: Ingestible) -> ItemDefinition {
        view(ingestible.formID, .ingestible, ingestible.fields, ingestible.itemValue)
    }

    fileprivate static func view(_ ingredient: Ingredient) -> ItemDefinition {
        view(ingredient.formID, .ingredient, ingredient.fields, ingredient.itemValue)
    }

    fileprivate static func view(_ item: MiscItem) -> ItemDefinition {
        view(item.formID, .miscellaneous, item.fields, item.itemValue)
    }

    fileprivate static func view(_ weapon: Weapon) -> ItemDefinition {
        view(weapon.formID, .weapon, weapon.fields, weapon.itemValue)
    }

    /// Shared projection for the six families that compose
    /// `InventoryItemFields`. ARMO has its own because its decoder predates
    /// that helper and keeps its fields flat.
    fileprivate static func view(
        _ formID: FormID,
        _ family: ItemDefinition.Family,
        _ fields: InventoryItemFields,
        _ itemValue: ItemValue
    ) -> ItemDefinition {
        ItemDefinition(
            formID: formID,
            family: family,
            editorID: fields.editorID,
            name: fields.name,
            value: itemValue.value,
            weight: itemValue.weight,
            keywords: fields.keywords.keywords
        )
    }
}
