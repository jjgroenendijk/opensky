// The arcane enchanter's menu over the enchanting rules: the four tabs it lists and
// its two actions, each answered in the game's words. See docs/engine/enchanting.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

extension MagicCoordinator.Enchanter {
    /// What the enchanter lists now: an empty set without a running game.
    public var enchanterChoices: EnchanterChoices {
        var choices = EnchanterChoices()
        guard
            let inventory = coordinator.world.inventory,
            let store = coordinator.enchantmentStore
        else { return choices }
        let table = coordinator.enchantingTable
        let records = coordinator.enchantingRecords
        let carried = Set(inventory.inventory(of: .player).stacks.map(\.item))
            .sorted { $0.rawValue < $1.rawValue }
        for item in carried {
            let entry = EnchanterItem(id: item, name: coordinator.world.itemName(item))
            if let profile = coordinator.weaponEnchantments.enchantmentProfile(of: item) {
                if
                    !profile.isStaff, let base = records.rootBase(of: profile),
                    !coordinator.world.itemHasKeyword("MagicDisallowEnchanting", on: item)
                {
                    var row = entry
                    row.isKnown = records.enchantingState.known.contains(base)
                    choices.disenchantable.append(row)
                }
            } else if
                table.enchantableKind(of: item) != nil,
                inventory.copies(of: item, in: .player).contains(where: { $0.enchantment == nil })
            {
                choices.enchantable.append(entry)
            }
        }
        choices.enchantments = records.enchantingState.known.compactMap { key in
            store.enchantment(key: key).map { EnchanterBase(key: key, name: $0.displayName) }
        }
        let souls = coordinator.texts.souls
        choices.gems = coordinator.soulTrapping.carriedGems(inventory)
            .filter { $0.soul != .empty }
            .map { gem in
                let soul = gem.soul
                return EnchanterGem(
                    item: gem.item, soul: soul.rawValue,
                    name: "\(coordinator.world.itemName(gem.item)) (\(souls.name(of: soul)))"
                )
            }
        return choices
    }

    /// Destroys `item` to learn its enchantment: the game's notice, or a readout line.
    public func disenchant(_ item: FormID) -> EnchanterAnswer {
        let texts = coordinator.texts.enchanting
        switch coordinator.enchantingRecords.disenchant(item) {
        case let .learned(_, base):
            return EnchanterAnswer(
                text: SettingTextFormat.fill(texts[.learned], [base]),
                done: true
            )
        case let .refused(refusal):
            return EnchanterAnswer(text: text(of: refusal), done: false)
        default:
            return EnchanterAnswer(text: "Cannot disenchant: no game running.", done: false)
        }
    }

    /// Why `selection` cannot be made, in the game's words; nil when it can.
    public func refusal(of selection: EnchanterSelection) -> String? {
        guard let parts = parts(of: selection) else {
            return coordinator.texts.enchanting[.mustChoose]
        }
        let preview = coordinator.enchantingTable.preview(
            parts.item, with: selection.bases, gem: parts.gem, name: selection.name
        )
        if case let .failure(refusal) = preview {
            return text(of: refusal)
        }
        return nil
    }

    /// Makes `selection`, spending its gem.
    public func enchant(_ selection: EnchanterSelection) -> EnchanterAnswer {
        guard let parts = parts(of: selection) else {
            return EnchanterAnswer(text: coordinator.texts.enchanting[.mustChoose], done: false)
        }
        let outcome = coordinator.enchantingTable.enchant(
            parts.item, with: selection.bases, gem: parts.gem, name: selection.name
        )
        switch outcome {
        case let .enchanted(item, name, _):
            return EnchanterAnswer(text: "\(item): \(name)", done: true)
        case let .refused(refusal):
            return EnchanterAnswer(text: text(of: refusal), done: false)
        default:
            return EnchanterAnswer(text: "Cannot enchant: no game running.", done: false)
        }
    }

    private func parts(of selection: EnchanterSelection) -> (item: FormID, gem: SoulGemCandidate)? {
        guard
            selection.isComplete, let item = selection.item, let chosen = selection.gem,
            let inventory = coordinator.world.inventory,
            let gem = coordinator.soulTrapping.carriedGems(inventory).first(where: {
                $0.item == chosen.item && $0.soul.rawValue == chosen.soul
            })
        else { return nil }
        return (item, gem)
    }

    private func text(of refusal: EnchantingRefusal) -> String {
        let texts = coordinator.texts.enchanting
        return switch refusal {
        case .alreadyKnown: texts[.alreadyKnown]
        case .baseDoesNotFit: texts[.doesNotFit]
        case .emptyGem: texts[.insufficientCharge]
        case .noBase: texts[.mustChoose]
        case .notCarried: "The item is not carried."
        case .notEnchanted: "The item has no enchantment."
        case .cannotDisenchant: "This item cannot be disenchanted."
        case .alreadyEnchanted: "The item is already enchanted."
        case .notEnchantable: "This item cannot be enchanted."
        case .unknownBase: "That enchantment is not known."
        case let .tooManyBases(allowed): "At most \(allowed) enchantments fit on one item."
        case .mixedPlugins: "These enchantments come from different plugins."
        }
    }
}
