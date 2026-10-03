// Read-only index of every carryable base record in one plugin, behind one view.
// Containers are indexed separately with `container(_:)`. Every item stacks by
// base FormID (`ItemDefinition.stackKey`), which holds until per-instance data
// exists (docs/engine/runtime-state.md). Single-plugin, raw-FormID keyed.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

/// The ENCH link a weapon or armor carries, resolved against the load order when
/// a resolver was supplied.
nonisolated public struct ItemEnchantment: Equatable, Sendable {
    /// EITM exactly as the record writes it, relative to its own plugin.
    public let link: FormID
    /// EAMT, the fully charged value. Weapons only: ARMO has no charge field.
    public let charge: UInt16?
    /// The winning ENCH identity, or nil when no resolver was supplied or the
    /// link is dangling.
    public let resolvedID: ResolvedFormID?
}

/// Resolves an item's EITM through an `EnchantmentStore`. Held by
/// `ItemDefinitionStore` so the per-record projections can name the winning
/// enchantment without each of them knowing about the load order.
nonisolated public struct ItemEnchantmentResolver: Sendable {
    public let store: EnchantmentStore
    /// The plugin the records being indexed came from; EITM is relative to it.
    public let pluginName: String

    public func resolve(_ link: FormID?, charge: UInt16?) -> ItemEnchantment? {
        guard let link else { return nil }
        return ItemEnchantment(
            link: link,
            charge: charge,
            resolvedID: store.resolvedID(link, fromPlugin: pluginName)
        )
    }

    public init(store: EnchantmentStore, pluginName: String) {
        self.store = store
        self.pluginName = pluginName
    }
}

/// One carryable base record, reduced to what inventory needs from all of
/// them. The `family` tag says which record type it came from, so a consumer
/// that needs the full decode can go back to the typed record.
nonisolated public struct ItemDefinition: Equatable, Sendable {
    /// Which record family the definition came from.
    public enum Family: String, Equatable, CaseIterable, Sendable {
        case armor = "ARMO"
        case ammunition = "AMMO"
        case apparatus = "APPA"
        case book = "BOOK"
        case ingestible = "ALCH"
        case ingredient = "INGR"
        case key = "KEYM"
        case miscellaneous = "MISC"
        case soulGem = "SLGM"
        case weapon = "WEAP"

        /// The top group this family lives in. `FourCC` only builds from a
        /// string literal, so the mapping is spelled out rather than derived
        /// from `rawValue`.
        public var recordType: FourCC {
            switch self {
            case .armor: "ARMO"
            case .ammunition: "AMMO"
            case .apparatus: "APPA"
            case .book: "BOOK"
            case .ingestible: "ALCH"
            case .ingredient: "INGR"
            case .key: "KEYM"
            case .miscellaneous: "MISC"
            case .soulGem: "SLGM"
            case .weapon: "WEAP"
            }
        }
    }

    public let formID: FormID
    public let family: Family
    public let editorID: String?
    /// FULL — display name. Nil on records that never surface in a menu.
    public let name: LString?
    /// Gold value before enchantment adjustments.
    public let value: Int32
    /// Carry weight.
    public let weight: Float
    /// KYWD links (vendor category, material, weapon type).
    public let keywords: [FormID]
    /// EITM and, on a weapon, EAMT. Nil on an unenchanted record and on every
    /// family that has no enchantment field at all.
    public let enchantment: ItemEnchantment?

    /// v1 stacking key: the base FormID. See the file header for why this is
    /// provisional.
    public var stackKey: UInt32 {
        formID.rawValue
    }
}

nonisolated public final class ItemDefinitionStore {
    /// Vanilla gold, `Gold001`: an ordinary `MISC` stack. Checked on the install:
    /// `MISC 0000000F — decoded MISC: editorID Gold001, value 1, weight 0.00`.
    public static let vanillaGoldFormID = FormID(0x0000_000F)

    /// Carryable item definitions, keyed by raw FormID.
    public let definitions: [UInt32: ItemDefinition]
    /// CONT decodes, keyed by raw FormID.
    public let containers: [UInt32: Container]
    /// WEAP decodes, keyed by raw FormID. Kept beside the unified view, because melee
    /// needs DNAM and INAM fields that `ItemDefinition` does not carry.
    public let weapons: [UInt32: Weapon]
    /// AMMO decodes, keyed by raw FormID, for archery's DATA `damage` and PROJ link.
    public let ammunition: [UInt32: Ammunition]
    /// ALCH decodes, keyed by raw FormID, for a potion's EFID/EFIT effect list.
    public let ingestibles: [UInt32: Ingestible]
    /// INGR decodes, keyed by raw FormID.
    public let ingredients: [UInt32: Ingredient]
    /// BOOK decodes, keyed by raw FormID, for the spell tome DATA union.
    public let books: [UInt32: Book]
    /// ARMO decodes, keyed by raw FormID, for the BOD2 armor type the armor skills
    /// level on.
    public let armor: [UInt32: Armor]
    /// SLGM decodes, keyed by raw FormID, for soul level and capacity.
    public let soulGems: [UInt32: SoulGem]
    /// APPA decodes, keyed by raw FormID, for quality.
    public let apparatus: [UInt32: Apparatus]
    /// PROJ decodes, keyed by raw FormID. Not carryable, but an arrow's shot needs
    /// its PROJ, so it is indexed here.
    public let projectiles: [UInt32: Projectile]

    /// Records that failed to decode, by family, so the real-data sweep can assert zero.
    public let skippedCounts: [ItemDefinition.Family: Int]
    /// Every skipped record with its first error per type, CONT and PROJ included.
    public let skippedRecords: SkippedRecords

    /// The load-order resolver behind `ItemDefinition.enchantment`, or nil when
    /// the store was built without one and the links stay unresolved.
    public let enchantments: ItemEnchantmentResolver?

    /// Builds the index. Supply `enchantments` to have every weapon and armor
    /// EITM resolved to the winning ENCH identity while the index is built;
    /// without it the links are still carried, just unresolved.
    public init(file: ESMFile, enchantments: ItemEnchantmentResolver? = nil) {
        self.enchantments = enchantments
        let localized = file.isLocalized
        var skipped = SkippedRecords()
        var definitions: [UInt32: ItemDefinition] = [:]
        for family in ItemDefinition.Family.allCases {
            let decoded = Self.decodeAll(family.recordType, in: file, skipped: &skipped) {
                try Self.definition(
                    record: $0,
                    family: family,
                    localized: localized,
                    enchantments: enchantments
                )
            }
            definitions.merge(decoded) { _, later in later }
        }
        self.definitions = definitions
        skippedCounts = Dictionary(
            uniqueKeysWithValues: ItemDefinition.Family.allCases.map {
                ($0, skipped.count(of: $0.recordType))
            }
        )
        containers = Self.decodeAll("CONT", in: file, skipped: &skipped) {
            try Container(record: $0, localized: localized)
        }
        projectiles = Self.decodeAll("PROJ", in: file, skipped: &skipped) {
            try Projectile(record: $0)
        }
        skippedRecords = skipped
        // The family loop above already counted these decoders' failures.
        var repeated = SkippedRecords()
        armor = Self.decodeAll("ARMO", in: file, skipped: &repeated) {
            try Armor(record: $0, localized: localized)
        }
        weapons = Self.decodeAll("WEAP", in: file, skipped: &repeated) {
            try Weapon(record: $0, localized: localized)
        }
        ammunition = Self.decodeAll("AMMO", in: file, skipped: &repeated) {
            try Ammunition(record: $0, localized: localized)
        }
        ingestibles = Self.decodeAll("ALCH", in: file, skipped: &repeated) {
            try Ingestible(record: $0, localized: localized)
        }
        ingredients = Self.decodeAll("INGR", in: file, skipped: &repeated) {
            try Ingredient(record: $0, localized: localized)
        }
        books = Self.decodeAll("BOOK", in: file, skipped: &repeated) {
            try Book(record: $0, localized: localized)
        }
        soulGems = Self.decodeAll("SLGM", in: file, skipped: &repeated) {
            try SoulGem(record: $0, localized: localized)
        }
        apparatus = Self.decodeAll("APPA", in: file, skipped: &repeated) {
            try Apparatus(record: $0, localized: localized)
        }
    }

    /// The armour type of a worn piece — heavy, light or clothing — or nil when
    /// the item is not armour or its record carries no BOD2 body template.
    public func armorType(_ id: FormID) -> ArmorType? {
        armor[id.rawValue]?.bodyTemplate?.armorType
    }

    /// The SPEL a spell tome teaches, or nil. The link is plugin-relative and raw;
    /// the caller resolves it.
    public func teachesSpell(_ id: FormID) -> FormID? {
        guard case let .spell(spell) = books[id.rawValue]?.teaches else { return nil }
        return spell
    }

    public func definition(_ id: FormID) -> ItemDefinition? {
        definitions[id.rawValue]
    }

    /// A linear scan, for a console-style command that names an item by editor ID.
    public func definition(editorID: String) -> ItemDefinition? {
        let wanted = editorID.lowercased()
        return definitions.values.first { $0.editorID?.lowercased() == wanted }
    }

    public func container(_ id: FormID) -> Container? {
        containers[id.rawValue]
    }

    /// The decoded WEAP behind an equipped item, or nil when the item is not a
    /// weapon.
    public func weapon(_ id: FormID) -> Weapon? {
        weapons[id.rawValue]
    }

    /// The arrow `id` names: its AMMO damage and its PROJ flight profile. Nil when
    /// `id` is not ammunition, or its PROJ is missing, hitscan, or has no speed.
    public func archeryAmmunition(_ id: FormID) -> ArcheryAmmunition? {
        guard
            let ammo = ammunition[id.rawValue],
            let link = ammo.projectile,
            let projectile = projectiles[link.rawValue],
            projectile.isBallistic
        else { return nil }
        return ArcheryAmmunition(ammunition: ammo, projectile: projectile)
    }

    /// The PROJ `id` names, as a flight profile, reached from an MGEF. Nil when the
    /// record is missing, hitscan, or has no launch speed; the spell is then refused
    /// and counted.
    public func projectileProfile(_ id: FormID) -> ProjectileProfile? {
        guard let projectile = projectiles[id.rawValue], projectile.isBallistic else {
            return nil
        }
        return ProjectileProfile(record: projectile)
    }

    /// Every definition of one family, in FormID order — a stable listing for
    /// the record dump and the sweep test.
    public func definitions(of family: ItemDefinition.Family) -> [ItemDefinition] {
        definitions.values
            .filter { $0.family == family }
            .sorted { $0.formID.rawValue < $1.formID.rawValue }
    }

    /// The ENCH behind an item's EITM, or nil when unenchanted or built without a
    /// resolver.
    public func enchantment(of definition: ItemDefinition) -> ResolvedEnchantment? {
        guard
            let resolver = enchantments,
            let resolvedID = definition.enchantment?.resolvedID
        else { return nil }
        return resolver.store.enchantment(resolvedID)
    }

    private static func definition(
        record: ESMRecord,
        family: ItemDefinition.Family,
        localized: Bool,
        enchantments: ItemEnchantmentResolver?
    ) throws -> ItemDefinition {
        switch family {
        case .armor:
            try view(Armor(record: record, localized: localized), enchantments)
        case .ammunition:
            try view(Ammunition(record: record, localized: localized))
        case .apparatus:
            try view(Apparatus(record: record, localized: localized))
        case .book:
            try view(Book(record: record, localized: localized))
        case .ingestible:
            try view(Ingestible(record: record, localized: localized))
        case .ingredient:
            try view(Ingredient(record: record, localized: localized))
        case .key:
            try view(KeyItem(record: record, localized: localized))
        case .miscellaneous:
            try view(MiscItem(record: record, localized: localized))
        case .soulGem:
            try view(SoulGem(record: record, localized: localized))
        case .weapon:
            try view(Weapon(record: record, localized: localized), enchantments)
        }
    }

    private static func decodeAll<Value>(
        _ type: FourCC,
        in file: ESMFile,
        skipped: inout SkippedRecords,
        using decode: (ESMRecord) throws -> Value
    ) -> [UInt32: Value] {
        var values: [UInt32: Value] = [:]
        for record in file.liveRecords(of: type, skipped: &skipped) {
            if let value = skipped.decode(record, using: decode) {
                values[record.formID] = value
            }
        }
        return values
    }
}

/// Per-family projections into `ItemDefinition`. Free functions in one
/// extension rather than an `ItemViewConvertible` protocol: the record structs
/// are plain decoders and none of them should grow a store-shaped conformance.
nonisolated extension ItemDefinitionStore {
    fileprivate static func view(
        _ armor: Armor,
        _ enchantments: ItemEnchantmentResolver?
    ) -> ItemDefinition {
        ItemDefinition(
            formID: armor.formID,
            family: .armor,
            editorID: armor.editorID,
            name: armor.name,
            value: armor.itemValue.value,
            weight: armor.itemValue.weight,
            keywords: armor.keywords.keywords,
            enchantment: enchantment(armor.enchantment, charge: nil, enchantments)
        )
    }

    /// The enchantment view for one record. The link is carried whether or not
    /// a resolver was supplied, so a store built without one still reports
    /// which items are enchanted.
    fileprivate static func enchantment(
        _ link: FormID?,
        charge: UInt16?,
        _ resolver: ItemEnchantmentResolver?
    ) -> ItemEnchantment? {
        guard let link else { return nil }
        guard let resolver else {
            return ItemEnchantment(link: link, charge: charge, resolvedID: nil)
        }
        return resolver.resolve(link, charge: charge)
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

    fileprivate static func view(_ key: KeyItem) -> ItemDefinition {
        view(key.formID, .key, key.fields, key.itemValue)
    }

    fileprivate static func view(_ gem: SoulGem) -> ItemDefinition {
        view(gem.formID, .soulGem, gem.fields, gem.itemValue)
    }

    fileprivate static func view(_ apparatus: Apparatus) -> ItemDefinition {
        view(apparatus.formID, .apparatus, apparatus.fields, apparatus.itemValue)
    }

    fileprivate static func view(
        _ weapon: Weapon,
        _ enchantments: ItemEnchantmentResolver?
    ) -> ItemDefinition {
        view(
            weapon.formID,
            .weapon,
            weapon.fields,
            weapon.itemValue,
            enchantment(
                weapon.enchantment,
                charge: weapon.enchantmentCharge,
                enchantments
            )
        )
    }

    /// Shared projection for the families that compose
    /// `InventoryItemFields`. ARMO has its own because its decoder predates
    /// that helper and keeps its fields flat.
    fileprivate static func view(
        _ formID: FormID,
        _ family: ItemDefinition.Family,
        _ fields: InventoryItemFields,
        _ itemValue: ItemValue,
        _ enchantment: ItemEnchantment? = nil
    ) -> ItemDefinition {
        ItemDefinition(
            formID: formID,
            family: family,
            editorID: fields.editorID,
            name: fields.name,
            value: itemValue.value,
            weight: itemValue.weight,
            keywords: fields.keywords.keywords,
            enchantment: enchantment
        )
    }
}
