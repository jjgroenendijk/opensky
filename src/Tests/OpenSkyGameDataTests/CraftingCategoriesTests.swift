// The forge tab of a created item: food, the first matching keyword, else Misc.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import Testing

struct CraftingCategoriesTests {
    private let iron = FormID(0x10)
    private let house = FormID(0x20)
    private let other = FormID(0x30)

    private var categories: CraftingCategories {
        CraftingCategories(tabByKeyword: [iron: .iron, house: .generic01])
    }

    @Test func theFirstKeywordInTheTableNamesTheTab() {
        #expect(categories.tab(forKeywords: [other, iron, house]) == .iron)
        #expect(categories.tab(forKeywords: [house, iron]) == .generic01)
    }

    @Test func foodGoesUnderFoodAndAnUnknownItemUnderMisc() {
        #expect(categories.tab(forKeywords: [iron], isFood: true) == .food)
        #expect(categories.tab(forKeywords: [other]) == .misc)
        #expect(categories.tab(forKeywords: []) == nil)
    }

    @Test func tabsFollowTheForgeOrder() {
        #expect(CraftingCategoryText.wood.rank < CraftingCategoryText.iron.rank)
        #expect(CraftingCategoryText.food.rank < CraftingCategoryText.generic01.rank)
        #expect(CraftingCategoryText.stalhrim.rank < CraftingCategoryText.misc.rank)
    }

    @Test func aDragonbornTabTitleIsTheMovieKey() {
        #expect(CraftingCategoryText.bonemold.fallback == "$Crafting_$DLC2ArmorBonemold")
    }
}
