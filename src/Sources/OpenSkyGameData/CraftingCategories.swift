// The tab a crafting station lists a recipe under: Food for food, else the first of the
// created item's keywords that names a material or a generic craftable keyword (`GCK1` to
// `GCK8`), else Misc. See docs/engine/crafting.md#crafting-menu.

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM

/// A crafting tab's title, in the order the forge lists its tabs. The raw value is the
/// setting's editor ID; the Dragonborn tabs have no setting and use the movie's own key.
nonisolated public enum CraftingCategoryText: String, GameSettingTextKey {
    case wood = "sWood"
    case hide = "sHide"
    case draugr = "sDraugr"
    case iron = "sIron"
    case studded = "sStudded"
    case imperial = "sImperial"
    case steel = "sSteel"
    case leather = "sLeather"
    case dwarven = "sDwarven"
    case elven = "sElven"
    case falmer = "sFalmer"
    case orcish = "sOrcish"
    case ebony = "sEbony"
    case glass = "sGlass"
    case dragon = "sDragon"
    case daedric = "sDaedric"
    case jewelry = "sJewelry"
    case food = "sFood"
    case generic01 = "sGenericCraftKeywordName01"
    case generic02 = "sGenericCraftKeywordName02"
    case generic03 = "sGenericCraftKeywordName03"
    case generic04 = "sGenericCraftKeywordName04"
    case generic05 = "sGenericCraftKeywordName05"
    case generic06 = "sGenericCraftKeywordName06"
    case generic07 = "sGenericCraftKeywordName07"
    case generic08 = "sGenericCraftKeywordName08"
    case bonemold = "$Crafting_$DLC2ArmorBonemold"
    case chitin = "$Crafting_$DLC2ArmorChitin"
    case nordic = "$Crafting_$DLC2ArmorNordic"
    case stalhrim = "$Crafting_$DLC2ArmorStalhrim"
    case misc = "sMisc"

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
        case .food: "FOOD"
        case .generic01: "HOUSE"
        case .generic02: "CONTAINERS"
        case .generic03: "FURNITURE"
        case .generic04: "WEAPON RACKS"
        case .generic05: "SHELVES"
        case .generic06: "EXTERIOR"
        case .generic07: "BUILDING MATERIALS"
        case .generic08: "BITS"
        // The movie's translation table turns the key into the title.
        case .bonemold, .chitin, .nordic, .stalhrim: rawValue
        case .misc: "MISC"
        }
    }

    /// The tab's place in the forge's tab list.
    public var rank: Int {
        Self.allCases.firstIndex(of: self) ?? Self.allCases.count
    }

    static let generic: [Self] = [
        .generic01, .generic02, .generic03, .generic04,
        .generic05, .generic06, .generic07, .generic08
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
            if
                let id = keywords.keyword(editorID: editorID)?.id,
                let local = itemPlugin.localFormID(of: id)
            {
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

    /// The tab of an item with `keywords`: food first, then the first keyword in the
    /// table, else Misc. An item with no keywords has no tab.
    public func tab(forKeywords keywords: [FormID], isFood: Bool = false) -> CraftingCategoryText? {
        if isFood {
            return .food
        }
        guard !keywords.isEmpty else { return nil }
        return keywords.lazy.compactMap { tabByKeyword[$0] }.first ?? .misc
    }

    static let genericTags = ["GCK1", "GCK2", "GCK3", "GCK4", "GCK5", "GCK6", "GCK7", "GCK8"]

    /// Material keywords of the five masters and the forge tab each goes under.
    static let materials: [String: CraftingCategoryText] = [
        "WeapMaterialIron": .iron, "ArmorMaterialIron": .iron, "ArmorMaterialIronBanded": .iron,
        "WeapMaterialSteel": .steel, "ArmorMaterialSteel": .steel,
        "ArmorMaterialSteelPlate": .steel,
        "ArmorMaterialScaled": .steel,
        "WeapMaterialDwarven": .dwarven, "ArmorMaterialDwarven": .dwarven,
        "WeapMaterialElven": .elven, "ArmorMaterialElven": .elven,
        "ArmorMaterialElvenGilded": .elven,
        "WeapMaterialOrcish": .orcish, "ArmorMaterialOrcish": .orcish,
        "WeapMaterialGlass": .glass, "ArmorMaterialGlass": .glass,
        "WeapMaterialEbony": .ebony, "ArmorMaterialEbony": .ebony,
        "WeapMaterialDaedric": .daedric, "ArmorMaterialDaedric": .daedric,
        "ArmorMaterialDragonplate": .dragon, "ArmorMaterialDragonscale": .dragon,
        "DLC1WeapMaterialDragonbone": .dragon,
        "ArmorMaterialLeather": .leather, "ArmorMaterialStormcloak": .leather,
        "ArmorMaterialHide": .hide,
        "ArmorMaterialStudded": .studded, "ArmorJewelry": .jewelry,
        "WeapMaterialImperial": .imperial, "ArmorMaterialImperialLight": .imperial,
        "ArmorMaterialImperialStudded": .imperial, "ArmorMaterialImperialHeavy": .imperial,
        "WeapMaterialDraugr": .draugr, "WeapMaterialDraugrHoned": .draugr,
        "WeapMaterialFalmer": .falmer, "WeapMaterialFalmerHoned": .falmer,
        "ArmorMaterialFalmer": .falmer, "WeapMaterialWood": .wood,
        "DLC2ArmorMaterialBonemoldLight": .bonemold, "DLC2ArmorMaterialBonemoldHeavy": .bonemold,
        "DLC2ArmorMaterialChitinLight": .chitin, "DLC2ArmorMaterialChitinHeavy": .chitin,
        "DLC2ArmorMaterialNordicLight": .nordic, "DLC2ArmorMaterialNordicHeavy": .nordic,
        "DLC2WeaponMaterialNordic": .nordic,
        "DLC2ArmorMaterialStalhrimLight": .stalhrim, "DLC2ArmorMaterialStalhrimHeavy": .stalhrim,
        "DLC2WeaponMaterialStalhrim": .stalhrim
    ]
}
