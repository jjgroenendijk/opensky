// Harvest and crafting actions of the inventory domain. The rules live in
// `WorldItemRuntime+Harvest` and `CraftingSession`. See docs/engine/crafting.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

extension InventoryCoordinator {
    public func wireCrafting(
        catalog: CraftingCatalog?,
        conditions: any RecipeConditionChecking,
        skills: any SkillUseReporting
    ) {
        craftingCatalog = catalog
        recipeConditions = conditions
        skillUses = skills
    }

    // MARK: - Harvest

    /// `interaction` with its runtime label: the game's verb, then a harvested plant, a
    /// locked target, or a perk's activate label, which wins.
    public func labelled(_ interaction: PlacedInteraction) -> PlacedInteraction {
        let context = ActivationPromptContext(
            isBook: world.isBook(interaction.base),
            isTheft: runtime?.isTheft(interaction) ?? false,
            isPlayerSneaking: world.isPlayerSneaking
        )
        let verb = ActivationPrompt.labelled(interaction, context: context, texts: activationTexts)
        let labelled = locks
            .labelled(runtime?.labelled(verb) ?? verb)
        guard let label = world.perkActivateLabel(for: interaction.reference) else {
            return labelled
        }
        return labelled.relabelled(label)
    }

    /// Refreshes the prompt, which now reads as harvested.
    public func harvest(_ interaction: PlacedInteraction) -> InventoryResult<ItemActionOutcome> {
        guard let runtime else { return InventoryResult(.unavailable) }
        do {
            let outcome = try runtime.harvest(
                interaction, at: harvestMoment, count: harvestCount(of: interaction)
            )
            let items = outcome.granted.map { "\($0.count) × \(name(of: $0.item))" }
            return InventoryResult(
                note(.harvested(plant: interaction.name, items: items)),
                commands: [.refreshInteractionTarget]
            )
        } catch {
            return InventoryResult(note(.failed(
                action: "Harvest",
                reason: String(describing: error)
            )))
        }
    }

    /// The day and the season of a harvest now.
    var harvestMoment: HarvestMoment {
        HarvestMoment(
            day: world.gameDaysPassed, season: world.gameMonth.flatMap(HarvestSeason.init(month:))
        )
    }

    /// Green Thumb sets Mod Ingredients Harvested to 2, with the produce bound as the item.
    func harvestCount(of interaction: PlacedInteraction) -> Int32 {
        let produce = interaction.produce?.ingredient
        let subject = runtime?.inventory.baselines.items.conditionSubject(of: produce)
        let value = world.perkModified(
            1,
            at: .modIngredientsHarvested,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player).binding(.item, to: subject),
            seams: ConditionContext()
        )
        return value.isFinite ? Int32(clamping: Int(max(1, value.rounded(.down)))) : 1
    }

    public func harvestInteractionTarget() -> InventoryResult<ItemActionOutcome> {
        guard let interaction = world.crosshairInteraction else {
            return InventoryResult(note(.nothingUnderCrosshair(verb: "harvest")))
        }
        return harvest(interaction)
    }

    public func resetHarvestOfInteractionTarget() -> InventoryResult<ItemActionOutcome> {
        guard let runtime else { return InventoryResult(.unavailable) }
        guard let interaction = world.crosshairInteraction else {
            return InventoryResult(note(.nothingUnderCrosshair(verb: "reset")))
        }
        do {
            try runtime.resetHarvest(interaction)
            return InventoryResult(
                note(.grewBack(interaction.name)), commands: [.refreshInteractionTarget]
            )
        } catch {
            return InventoryResult(note(.failed(
                action: "Reset",
                reason: String(describing: error)
            )))
        }
    }

    // MARK: - Crafting

    /// Opens a session for a station activation, replacing any open one.
    @discardableResult
    public func openCraftingSession(_ event: CraftingActivationEvent) -> CraftingActionOutcome {
        guard let runtime else { return noteCraft(.unavailable) }
        guard let craftingCatalog else { return noteCraft(.noRecipeData) }
        crafting = CraftingSession(
            event: event,
            catalog: craftingCatalog,
            inventory: runtime.inventory,
            player: runtime.player,
            conditions: recipeConditions,
            skills: skillUses,
            skillUse: craftingSkillUse
        )
        alchemySelection = crafting?.station.brews == true ? [] : nil
        if alchemySelection != nil {
            let carried = alchemyIngredients.count
            return noteCraft(.openedLab(event.interaction.name, ingredients: carried))
        }
        let count = crafting?.recipes.count ?? 0
        return noteCraft(.opened(station: event.interaction.name, recipes: count))
    }

    /// The dev control: a session at a station base, without walking to one.
    @discardableResult
    public func openCraftingSession(station editorID: String) -> CraftingActionOutcome {
        guard let choice = craftingCatalog?.stations.first(where: { $0.editorID == editorID })
        else { return noteCraft(.noStationNamed(editorID)) }
        let interaction = PlacedInteraction(
            reference: choice.base,
            base: choice.base,
            position: .zero,
            name: choice.editorID,
            action: .use,
            actionLabel: InteractionAction.use.defaultLabel,
            sounds: nil,
            station: CraftingStation(workbench: choice.workbench, keywords: choice.keywords)
        )
        guard let event = CraftingActivationEvent(interaction: interaction) else {
            return noteCraft(.notAStation(editorID))
        }
        return openCraftingSession(event)
    }

    @discardableResult
    public func craft(_ recipe: ResolvedFormID) -> CraftingActionOutcome {
        guard let crafting else { return noteCraft(.notOpen) }
        do {
            let outcome = try crafting.craft(recipe)
            if let step = outcome.improved {
                let from = qualityName(step.from, of: outcome.created.item)
                let to = qualityName(step.to, of: outcome.created.item)
                let item = name(of: outcome.created.item)
                return noteCraft(.improved(item: item, from: from, to: to))
            }
            storyEvents?.reportStoryEvent(.craft(
                actor: .player,
                workbench: runtime?.references?
                    .referenceEntry(formID: crafting.interaction.reference)?.key,
                location: nil,
                created: outcome.created.item
            ))
            return noteCraft(.crafted(
                count: outcome.created.count, item: name(of: outcome.created.item)
            ))
        } catch {
            return noteCraft(.craftFailed(reason: String(describing: error)))
        }
    }

    @discardableResult
    public func closeCraftingSession() -> CraftingActionOutcome {
        guard crafting != nil else { return noteCraft(.notOpen) }
        crafting = nil
        alchemySelection = nil
        return noteCraft(.closed)
    }

    @discardableResult
    private func noteCraft(_ outcome: CraftingActionOutcome) -> CraftingActionOutcome {
        lastCraft = outcome
        return outcome
    }
}
