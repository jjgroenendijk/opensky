// The tab a crafting station lists a recipe under, from the created item's keywords: the
// generic craftable keywords of the default objects (`GCK1` to `GCKX`), else the item's
// material. Each tab's title is a string setting. See docs/engine/crafting.md#crafting-menu.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

/// A crafting tab's title. The raw value is the setting's editor ID.
nonisolated public enum CraftingCategoryText: String, GameSettingTextKey {
    case iron = "sIron"
    case steel = "sSteel"
    case dwarven = "sDwarven"
    case elven = "sElven"
    case orcish = "sOrcish"
    case glass = "sGlass"
    case ebony = "sEbony"
    case daedric = "sDaedric"
    case dragon = "sDragon"
    case leather = "sLeather"
    case hide = "sHide"
    case studded = "sStudded"
    case jewelry = "sJewelry"
    case imperial = "sImperial"
    case draugr = "sDraugr"
    case falmer = "sFalmer"
    case wood = "sWood"
    case generic01 = "sGenericCraftKeywordName01"
    case generic02 = "sGenericCraftKeywordName02"
    case generic03 = "sGenericCraftKeywordName03"
    case generic04 = "sGenericCraftKeywordName04"
    case generic05 = "sGenericCraftKeywordName05"
    case generic06 = "sGenericCraftKeywordName06"
    case generic07 = "sGenericCraftKeywordName07"
    case generic08 = "sGenericCraftKeywordName08"
    case generic09 = "sGenericCraftKeywordName09"
    case generic10 = "sGenericCraftKeywordName10"

    public var fallback: String {
        switch self {
        case .iron: "IRON"
        case .steel: "STEEL"
        case .dwarven: "DWARVEN"
        case .elven: "ELVEN"
        case .orcish: "ORCISH"
        case .glass: "GLASS"
        case .ebony: "EBONY"
        case .daedric: "DAEDRIC"
        case .dragon: "DRAGON"
        case .leather: "LEATHER"
        case .hide: "HIDE"
        case .studded: "STUDDED"
        case .jewelry: "JEWELRY"
        case .imperial: "IMPERIAL"
        case .draugr: "DRAUGR"
        case .falmer: "FALMER"
        case .wood: "WOOD"
        case .generic01: "HOUSE"
        case .generic02: "CONTAINERS"
        case .generic03: "FURNITURE"
        case .generic04: "WEAPON RACKS"
        case .generic05: "SHELVES"
        case .generic06: "EXTERIOR"
        case .generic07: "BUILDING MATERIALS"
        case .generic08: "BITS"
        case .generic09: "BOBS"
        case .generic10: "AETHERIUM"
        }
    }

    /// A generic craftable keyword's tab, which wins over a material.
    var isGeneric: Bool {
        rawValue.hasPrefix("sGenericCraftKeywordName")
    }

    static let generic: [Self] = [
        .generic01, .generic02, .generic03, .generic04, .generic05,
        .generic06, .generic07, .generic08, .generic09, .generic10
    ]
}

nonisolated public struct CraftingCategories: Equatable, Sendable {
    /// Item-plugin keyword FormID -> the tab it puts an item under.
    public let tabByKeyword: [FormID: CraftingCategoryText]

    public static let empty = Self(tabByKeyword: [:])

    public init(tabByKeyword: [FormID: CraftingCategoryText]) {
        self.tabByKeyword = tabByKeyword
    }

    /// Reads keyword editor IDs and the default objects of `loadOrder`, in `itemPlugin` terms.
    public init(loadOrder: LoadOrderPlugins, itemPlugin: FormIDResolver) {
        let index = RecordIndex(
            plugins: loadOrder.plugins.map { ($0.name, $0.file) }, recordTypes: ["KYWD", "DOBJ"]
        )
        let keywords = KeywordStore(index: index)
        let defaults = DefaultObjectStore(index: index)
        var table: [FormID: CraftingCategoryText] = [:]
        for (editorID, tab) in Self.materials {
            if let id = keywords.keyword(editorID: editorID)?.id, let local = itemPlugin.localFormID(of: id) {
                table[local] = tab
            }
        }
        for (tag, tab) in zip(Self.genericTags, CraftingCategoryText.generic) {
            if let id = defaults.object(tag: tag), let local = itemPlugin.localFormID(of: id) {
                table[local] = tab
            }
        }
        self.init(tabByKeyword: table)
    }

    /// The tab of an item with `keywords`. A generic craftable keyword wins over a
    /// material, because a HearthFire part can carry both.
    public func tab(forKeywords keywords: [FormID]) -> CraftingCategoryText? {
        let tabs = keywords.compactMap { tabByKeyword[$0] }
        return tabs.first(where: \.isGeneric) ?? tabs.first
    }

    static let genericTags = ["GCK1", "GCK2", "GCK3", "GCK4", "GCK5", "GCK6", "GCK7", "GCK8", "GCK9", "GCKX"]

    /// Material keywords of the five masters and the forge tab each goes under.
    static let materials: [String: CraftingCategoryText] = [
        "WeapMaterialIron": .iron, "ArmorMaterialIron": .iron, "ArmorMaterialIronBanded": .iron,
        "WeapMaterialSteel": .steel, "ArmorMaterialSteel": .steel, "ArmorMaterialSteelPlate": .steel,
        "WeapMaterialDwarven": .dwarven, "ArmorMaterialDwarven": .dwarven,
        "WeapMaterialElven": .elven, "ArmorMaterialElven": .elven, "ArmorMaterialElvenGilded": .elven,
        "WeapMaterialOrcish": .orcish, "ArmorMaterialOrcish": .orcish,
        "WeapMaterialGlass": .glass, "ArmorMaterialGlass": .glass,
        "WeapMaterialEbony": .ebony, "ArmorMaterialEbony": .ebony,
        "WeapMaterialDaedric": .daedric, "ArmorMaterialDaedric": .daedric,
        "ArmorMaterialDragonplate": .dragon, "ArmorMaterialDragonscale": .dragon,
        "DLC1WeapMaterialDragonbone": .dragon,
        "ArmorMaterialLeather": .leather, "ArmorMaterialHide": .hide,
        "ArmorMaterialStudded": .studded, "ArmorJewelry": .jewelry,
        "WeapMaterialImperial": .imperial, "ArmorMaterialImperialLight": .imperial,
        "ArmorMaterialImperialStudded": .imperial, "ArmorMaterialImperialHeavy": .imperial,
        "WeapMaterialDraugr": .draugr, "WeapMaterialDraugrHoned": .draugr,
        "WeapMaterialFalmer": .falmer, "WeapMaterialFalmerHoned": .falmer,
        "ArmorMaterialFalmer": .falmer, "WeapMaterialWood": .wood
    ]
}
