// Harvest and crafting actions of the inventory domain. The rules live in
// `WorldItemRuntime+Harvest` and `CraftingSession`. See docs/engine/crafting.md.

import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData
public import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
public import OpenSkyWorldInterface
import OpenSkyWorldState

extension InventoryCoordinator.CraftingBench {
    // MARK: - Harvest

    /// `interaction` with its runtime label: the game's verb, then a harvested plant, a
    /// locked target, or a perk's activate label, which wins.
    public func labelled(_ interaction: PlacedInteraction) -> PlacedInteraction {
        let context = ActivationPromptContext(
            isBook: coordinator.world.isBook(interaction.base),
            isTheft: coordinator.runtime?.isTheft(interaction) ?? false,
            isPlayerSneaking: coordinator.world.isPlayerSneaking,
            isOpen: coordinator.runtime?.isOpen(interaction) ?? false
        )
        let verb = ActivationPrompt.labelled(
            interaction,
            context: context,
            texts: coordinator.texts.activation
        )
        let labelled = coordinator.locks
            .labelled(coordinator.runtime?.labelled(verb) ?? verb)
        guard let label = coordinator.world.perkActivateLabel(for: interaction.reference) else {
            return labelled
        }
        return labelled.relabelled(label)
    }

    /// Refreshes the prompt, which now reads as harvested.
    public func harvest(_ interaction: PlacedInteraction) -> InventoryResult<ItemActionOutcome> {
        guard let runtime = coordinator.runtime else { return InventoryResult(.unavailable) }
        do {
            let outcome = try runtime.harvest(
                interaction, at: harvestMoment, count: harvestCount(of: interaction)
            )
            let items = outcome.granted.map { "\($0.count) × \(coordinator.name(of: $0.item))" }
            return InventoryResult(
                coordinator.note(.harvested(plant: interaction.name, items: items)),
                commands: [.refreshInteractionTarget]
            )
        } catch {
            return InventoryResult(coordinator.note(.failed(
                action: "Harvest",
                reason: String(describing: error)
            )))
        }
    }

    /// The day and the season of a harvest now.
    var harvestMoment: HarvestMoment {
        HarvestMoment(
            day: coordinator.world.gameDaysPassed,
            season: coordinator.world.gameMonth.flatMap(HarvestSeason.init(month:))
        )
    }

    /// Green Thumb sets Mod Ingredients Harvested to 2, with the produce bound as the item.
    func harvestCount(of interaction: PlacedInteraction) -> Int32 {
        let produce = interaction.produce?.ingredient
        let subject = coordinator.runtime?.inventory.baselines.items.conditionSubject(of: produce)
        let value = coordinator.world.perkModified(
            1,
            at: .modIngredientsHarvested,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player).binding(.item, to: subject),
            seams: ConditionContext()
        )
        return value.isFinite ? Int32(clamping: Int(max(1, value.rounded(.down)))) : 1
    }

    public func harvestInteractionTarget() -> InventoryResult<ItemActionOutcome> {
        guard let interaction = coordinator.world.crosshairInteraction else {
            return InventoryResult(coordinator.note(.nothingUnderCrosshair(verb: "harvest")))
        }
        return harvest(interaction)
    }

    // MARK: - Crafting

    /// Opens a session for a station activation, replacing any open one.
    @discardableResult
    public func openCraftingSession(_ event: CraftingActivationEvent) -> CraftingActionOutcome {
        guard let runtime = coordinator.runtime else { return noteCraft(.unavailable) }
        guard let craftingCatalog = coordinator.craftingCatalog
        else { return noteCraft(.noRecipeData) }
        coordinator.crafting = CraftingSession(
            event: event,
            catalog: craftingCatalog,
            inventory: runtime.inventory,
            player: runtime.player,
            conditions: coordinator.recipeConditions,
            skills: coordinator.skillUses,
            skillUse: coordinator.craftingSkillUse
        )
        coordinator.alchemySelection = coordinator.crafting?.station.brews == true ? [] : nil
        if coordinator.alchemySelection != nil {
            let carried = coordinator.alchemyLab.alchemyIngredients.count
            return noteCraft(.openedLab(event.interaction.name, ingredients: carried))
        }
        let count = coordinator.crafting?.recipes.count ?? 0
        return noteCraft(.opened(station: event.interaction.name, recipes: count))
    }

    @discardableResult
    public func craft(_ recipe: ResolvedFormID) -> CraftingActionOutcome {
        guard let crafting = coordinator.crafting else { return noteCraft(.notOpen) }
        do {
            let outcome = try crafting.craft(recipe)
            if let step = outcome.improved {
                let from = coordinator.craftingReadout.qualityName(
                    step.from,
                    of: outcome.created.item
                )
                let to = coordinator.craftingReadout.qualityName(step.to, of: outcome.created.item)
                let item = coordinator.name(of: outcome.created.item)
                return noteCraft(.improved(item: item, from: from, to: to))
            }
            coordinator.storyEvents?.reportStoryEvent(.craft(
                actor: .player,
                workbench: coordinator.runtime?.references?
                    .referenceEntry(formID: crafting.interaction.reference)?.key,
                location: nil,
                created: outcome.created.item
            ))
            return noteCraft(.crafted(
                count: outcome.created.count, item: coordinator.name(of: outcome.created.item)
            ))
        } catch {
            if
                let error = error as? CraftingError,
                let refusal = CraftingRefusal.text(for: error, improving: crafting.station.improves)
            {
                return noteCraft(.refused(refusal))
            }
            return noteCraft(.craftFailed(reason: String(describing: error)))
        }
    }

    @discardableResult
    public func closeCraftingSession() -> CraftingActionOutcome {
        guard coordinator.crafting != nil else { return noteCraft(.notOpen) }
        coordinator.crafting = nil
        coordinator.alchemySelection = nil
        return noteCraft(.closed)
    }

    @discardableResult
    private func noteCraft(_ outcome: CraftingActionOutcome) -> CraftingActionOutcome {
        coordinator.lastCraft = outcome
        return outcome
    }
}
