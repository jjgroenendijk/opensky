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

/// The ENCH link a weapon or a piece of armor carries, already resolved
/// against the load order where a resolver was supplied (issue #466). The
/// equipment runtime reads the resolved identity instead of walking plugins
/// again for every equip.
nonisolated struct ItemEnchantment: Equatable {
    /// EITM exactly as the record writes it, relative to its own plugin.
    let link: FormID
    /// EAMT, the fully charged value. Weapons only: ARMO has no charge field.
    let charge: UInt16?
    /// The winning ENCH identity, or nil when no resolver was supplied or the
    /// link is dangling.
    let resolvedID: ResolvedFormID?
}

/// Resolves an item's EITM through an `EnchantmentStore`. Held by
/// `ItemDefinitionStore` so the per-record projections can name the winning
/// enchantment without each of them knowing about the load order.
nonisolated struct ItemEnchantmentResolver {
    let store: EnchantmentStore
    /// The plugin the records being indexed came from; EITM is relative to it.
    let pluginName: String

    func resolve(_ link: FormID?, charge: UInt16?) -> ItemEnchantment? {
        guard let link else { return nil }
        return ItemEnchantment(
            link: link,
            charge: charge,
            resolvedID: store.resolvedID(link, fromPlugin: pluginName)
        )
    }
}

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
    /// EITM and, on a weapon, EAMT. Nil on an unenchanted record and on every
    /// family that has no enchantment field at all.
    let enchantment: ItemEnchantment?

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
    /// WEAP decodes, keyed by raw FormID (issue #195).
    ///
    /// Kept beside the unified views rather than folded into them: melee
    /// combat needs DNAM `reach`, `speed` and `stagger` and the INAM impact
    /// link, and `ItemDefinition` deliberately carries only what every family
    /// has in common. A second dictionary over the same records costs one
    /// pointer per weapon and keeps the common view from growing a
    /// weapon-shaped hole every other family fills with nil.
    let weapons: [UInt32: Weapon]
    /// AMMO decodes, keyed by raw FormID (issue #196).
    ///
    /// Beside the unified views for the same reason the WEAP decodes are:
    /// archery needs DATA `damage` and the PROJ link, and `ItemDefinition`
    /// carries only what every family has in common.
    let ammunition: [UInt32: Ammunition]
    /// ALCH decodes, keyed by raw FormID (issue #469).
    ///
    /// Beside the unified views for the same reason the WEAP and AMMO decodes
    /// are: consuming a potion needs its EFID/EFIT effect list, and
    /// `ItemDefinition` deliberately carries only what every family has in
    /// common.
    let ingestibles: [UInt32: Ingestible]
    /// INGR decodes, keyed by raw FormID (issue #469). Beside the ALCH decodes
    /// for the same reason.
    let ingredients: [UInt32: Ingredient]
    /// PROJ decodes, keyed by raw FormID (issue #196).
    ///
    /// PROJ is not a carryable family and has no `ItemDefinition` view at all,
    /// but the record an arrow points at is exactly what a shot needs next, so
    /// it is indexed here rather than in a second store that would have to be
    /// built from the same file and handed around beside this one.
    let projectiles: [UInt32: Projectile]

    /// Records that failed to decode, by family — surfaced so the real-data
    /// sweep can assert zero rather than silently indexing fewer items.
    let skippedCounts: [ItemDefinition.Family: Int]

    /// The load-order resolver behind `ItemDefinition.enchantment`, or nil when
    /// the store was built without one and the links stay unresolved.
    let enchantments: ItemEnchantmentResolver?

    /// Builds the index. Supply `enchantments` to have every weapon and armor
    /// EITM resolved to the winning ENCH identity while the index is built;
    /// without it the links are still carried, just unresolved.
    init(file: ESMFile, enchantments: ItemEnchantmentResolver? = nil) {
        self.enchantments = enchantments
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        var definitions: [UInt32: ItemDefinition] = [:]
        var skipped: [ItemDefinition.Family: Int] = [:]
        for family in ItemDefinition.Family.allCases {
            var familySkips = 0
            for record in Self.records(of: family.recordType, in: file) {
                guard
                    let definition = Self.definition(
                        record: record,
                        family: family,
                        localized: localized,
                        enchantments: enchantments
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
        weapons = Self.records(of: "WEAP", in: file)
            .compactMap { try? Weapon(record: $0, localized: localized) }
            .reduce(into: [:]) { $0[$1.formID.rawValue] = $1 }
        ammunition = Self.records(of: "AMMO", in: file)
            .compactMap { try? Ammunition(record: $0, localized: localized) }
            .reduce(into: [:]) { $0[$1.formID.rawValue] = $1 }
        projectiles = Self.records(of: "PROJ", in: file)
            .compactMap { try? Projectile(record: $0) }
            .reduce(into: [:]) { $0[$1.formID.rawValue] = $1 }
        ingestibles = Self.records(of: "ALCH", in: file)
            .compactMap { try? Ingestible(record: $0, localized: localized) }
            .reduce(into: [:]) { $0[$1.formID.rawValue] = $1 }
        ingredients = Self.records(of: "INGR", in: file)
            .compactMap { try? Ingredient(record: $0, localized: localized) }
            .reduce(into: [:]) { $0[$1.formID.rawValue] = $1 }
    }

    /// What consuming `id` applies, or nil when it is not something an actor
    /// can eat or drink (issue #469).
    func magicItemUse(_ id: FormID) -> MagicItemUse? {
        if let ingestible = ingestibles[id.rawValue] {
            return MagicItemUse(
                item: id,
                kind: .potion,
                effects: ingestible.effects,
                consumeSound: ingestible.consumeSound
            )
        }
        guard let ingredient = ingredients[id.rawValue] else { return nil }
        // Eating a raw ingredient applies only its first effect. UESP's
        // "Skyrim:Alchemy Effects" states it directly: "Ingredients listed in
        // bold have that effect as their first, meaning that eating a sample of
        // that ingredient will provide a small version of that effect."
        // <https://en.uesp.net/wiki/Skyrim:Alchemy_Effects>
        return MagicItemUse(
            item: id,
            kind: .ingredient,
            effects: Array(ingredient.effects.prefix(1)),
            consumeSound: nil
        )
    }

    func definition(_ id: FormID) -> ItemDefinition? {
        definitions[id.rawValue]
    }

    func container(_ id: FormID) -> Container? {
        containers[id.rawValue]
    }

    /// The decoded WEAP behind an equipped item, or nil when the item is not a
    /// weapon.
    func weapon(_ id: FormID) -> Weapon? {
        weapons[id.rawValue]
    }

    /// The arrow `id` names, as everything a shot needs from it: its AMMO
    /// damage and the flight profile of the PROJ it launches (issue #196).
    ///
    /// Nil when `id` is not ammunition, or when the PROJ it names is missing
    /// or is not something the flight model can integrate — a hitscan record,
    /// or one with no launch speed. An arrow that cannot fly is better
    /// reported as no arrow than as a projectile that stands still where the
    /// bow is.
    func archeryAmmunition(_ id: FormID) -> ArcheryAmmunition? {
        guard
            let ammo = ammunition[id.rawValue],
            let link = ammo.projectile,
            let projectile = projectiles[link.rawValue],
            projectile.isBallistic
        else { return nil }
        return ArcheryAmmunition(ammunition: ammo, projectile: projectile)
    }

    /// Every definition of one family, in FormID order — a stable listing for
    /// the record dump and the sweep test.
    func definitions(of family: ItemDefinition.Family) -> [ItemDefinition] {
        definitions.values
            .filter { $0.family == family }
            .sorted { $0.formID.rawValue < $1.formID.rawValue }
    }

    /// The ENCH behind an item's EITM, or nil when the item is unenchanted or
    /// the store was built without a resolver (issue #466). The equipment
    /// runtime reads this instead of re-walking plugins.
    func enchantment(of definition: ItemDefinition) -> ResolvedEnchantment? {
        guard
            let resolver = enchantments,
            let resolvedID = definition.enchantment?.resolvedID
        else { return nil }
        return resolver.store.enchantment(resolvedID)
    }

    /// Decodes one record into the unified view. Returns nil when the typed
    /// decode throws, which the caller counts as a skip.
    private static func definition(
        record: ESMRecord,
        family: ItemDefinition.Family,
        localized: Bool,
        enchantments: ItemEnchantmentResolver?
    ) -> ItemDefinition? {
        switch family {
        case .armor:
            (try? Armor(record: record, localized: localized))
                .map { view($0, enchantments) }
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
            (try? Weapon(record: record, localized: localized))
                .map { view($0, enchantments) }
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

    /// Shared projection for the six families that compose
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
