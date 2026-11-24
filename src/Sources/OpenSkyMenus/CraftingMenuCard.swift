// The crafting menu's item card, the line under it, the station's description, and the
// skill bar in the bottom bar. See docs/engine/crafting.md#item-card-and-skill-bar.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyInventoryInterface

/// The open station's skill as the bottom bar shows it.
nonisolated public struct CraftingSkillBar: Equatable, Sendable {
    public let name: String
    public let level: Int
    /// Experience toward the next level, 0 to 1.
    public let progress: Float

    public init(name: String, level: Int, progress: Float) {
        self.name = name
        self.level = level
        self.progress = progress
    }
}

extension CraftingMenuCoordinator {
    /// The item the selected row stands for, and the line under its card.
    func cardSubject(of row: ItemListRow) -> (item: FormID?, line: String?) {
        let index = Int(row.tag)
        switch mode {
        case .enchanting:
            return (enchanting.item(of: row), nil)
        case .alchemy:
            return (ingredients.indices.contains(index) ? ingredients[index].id : nil, nil)
        case .create, .improve:
            guard recipes.indices.contains(index) else { return (nil, nil) }
            return (recipes[index].created, recipes[index].requirements)
        }
    }

    /// Sent on each publish, because a craft changes the skill.
    func publishHeader(_ runtime: SWFMovieRuntime) {
        CraftingMenuMovieBridge.publishHeader(
            description: world?.craftingDescription ?? "", skill: world?.craftingSkill,
            runtime: runtime
        )
    }

    func publishCard(_ runtime: SWFMovieRuntime) {
        if let info = sliderCard() {
            CraftingMenuMovieBridge.publishCard(info, line: nil, runtime: runtime)
            return
        }
        let subject: (item: FormID?, line: String?) =
            model.selected.map(cardSubject) ?? (nil, nil)
        let card = subject.item.flatMap { world?.craftingItemCard($0) }
        CraftingMenuMovieBridge.publishCard(
            card.map(InventoryMenuMovieBridge.itemCardInfo), line: subject.line, runtime: runtime
        )
    }
}

extension CraftingMenuCoordinator {
    /// While the slider is open the card shows the item to make: its name, the uses at
    /// the chosen magnitude, and the chosen enchantments.
    func sliderCard() -> [String: AS2Value]? {
        guard isSliderOpen, let slider = enchanting.slider else { return nil }
        let selection = enchanting.selection
        let name = selection.name
            ?? selection.item.flatMap { world?.craftingItemCard($0)?.name } ?? ""
        let effects = (world?.enchanter.enchanterChoices?.enchantments ?? [])
            .filter { selection.bases.contains($0.key) }.map(\.name)
        return CraftingMenuMovieBridge.sliderCardInfo(
            name: name, uses: slider.uses, effects: effects.joined(separator: ", ")
        )
    }
}

nonisolated extension CraftingMenuMovieBridge {
    /// `ICT_CRAFT_ENCHANTING` in the movie's `InventoryDefines`.
    static let craftEnchantingCardType = 15

    /// With `sliderShown` the card goes to its `Craft_Enchanting` frame, which shows
    /// `totalCharges` beside "Charges" and `effects` under it.
    static func sliderCardInfo(name: String, uses: Int, effects: String) -> [String: AS2Value] {
        [
            "type": .integer(craftEnchantingCardType),
            "sliderShown": .boolean(true),
            "name": .string(name),
            "totalCharges": .integer(uses),
            "effects": .string(effects)
        ]
    }

    /// `ItemInfo.itemInfo` takes the card as the inventory builds it, and the menu's
    /// `FadeInfoCard` shows or hides it with the line under it. Without a card the
    /// card fades out.
    static func publishCard(
        _ info: [String: AS2Value]?, line: String?, runtime: SWFMovieRuntime
    ) {
        MenuMovieText.assign(
            .boolean(line == nil), member: "bHideAdditionalDescription", atPath: menuPath,
            runtime: runtime
        )
        MenuMovieText.set(line ?? "", atPath: additionalDescriptionPath, runtime: runtime)
        guard let info else {
            runtime.callMovie("FadeInfoCard", atPath: menuPath, arguments: [.boolean(false)])
            return
        }
        let object = runtime.runtime.makeObject()
        for name in info.keys.sorted() {
            object.assign(info[name] ?? .undefined, for: name)
        }
        runtime.callMovie("__set__itemInfo", atPath: itemInfoPath, arguments: [.object(object)])
        runtime.callMovie("FadeInfoCard", atPath: menuPath, arguments: [.boolean(true)])
    }

    /// The description replaces the movie's own "Select items to craft".
    /// `UpdateCraftingInfo(skill, level, percent)` turns the bottom bar into the skill bar.
    static func publishHeader(
        description: String, skill: CraftingSkillBar?, runtime: SWFMovieRuntime
    ) {
        MenuMovieText.set(description, atPath: menuDescriptionPath, runtime: runtime)
        guard let skill else { return }
        runtime.callMovie(
            "UpdateCraftingInfo", atPath: bottomBarPath,
            arguments: [
                .string(skill.name), .integer(skill.level),
                .number(Double(skill.progress * 100))
            ]
        )
    }
}
