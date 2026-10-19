// Alchemy: choose two or three carried ingredients at a lab, see what they make, and
// brew it. Eating an ingredient teaches its first effect. The rules live in
// `AlchemyRules`. See docs/engine/alchemy.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState

/// One carried ingredient at the lab.
nonisolated public struct AlchemyIngredientReadout: Equatable, Sendable {
    public let id: FormID
    public let name: String
    public let count: Int32
    /// Each effect's name when the player knows it, by index; nil for an unknown one.
    public let effects: [String?]
    public let isChosen: Bool

    public init(id: FormID, name: String, count: Int32, effects: [String?], isChosen: Bool) {
        self.id = id
        self.name = name
        self.count = count
        self.effects = effects
        self.isChosen = isChosen
    }

    public var effectsText: String {
        effects.map { $0 ?? "?" }.joined(separator: ", ")
    }
}

/// What the chosen ingredients would make.
nonisolated public struct AlchemyPreview: Equatable, Sendable {
    /// Nil when the ingredients share no effect.
    public let name: String?
    public let value: Int32
    /// One line per effect: name, magnitude, and duration.
    public let effects: [String]

    public init(name: String?, value: Int32, effects: [String]) {
        self.name = name
        self.value = value
        self.effects = effects
    }

    public var text: String {
        guard let name else { return "No shared effect: the brew fails." }
        return "Makes \(name), worth \(value) gold: \(effects.joined(separator: "; "))."
    }
}

extension InventoryCoordinator {
    /// The Alchemy skill's actor-value index.
    public static let alchemySkill: Int32 = 16
    public static let alchemyIngredientLimit = 3

    public func wireAlchemy(
        effects: MagicEffectStore?,
        pluginName: String,
        settings: AlchemySettings,
        texts: AlchemyTexts
    ) {
        magicEffects = effects
        magicItemPlugin = pluginName
        alchemySettings = settings
        alchemyTexts = texts
        registerCreatedPotions()
    }

    public var createdPotions: CreatedPotionState {
        runtime?.store.component(CreatedPotionState.self, for: .player) ?? CreatedPotionState()
    }

    public var ingredientKnowledge: IngredientKnowledgeState {
        runtime?.store.component(IngredientKnowledgeState.self, for: .player)
            ?? IngredientKnowledgeState()
    }

    /// Puts the brewed potions of the running game in the item index. Call it after a
    /// save is loaded, because no plugin holds them.
    public func registerCreatedPotions() {
        guard let items = runtime?.inventory.baselines.items else { return }
        items.removeCreatedPotions()
        for potion in createdPotions.potions {
            items.registerCreated(potion.ingestible)
        }
    }

    // MARK: - Lab

    /// Every carried ingredient, by name.
    public var alchemyIngredients: [AlchemyIngredientReadout] {
        guard let runtime else { return [] }
        let items = runtime.inventory.baselines.items
        let knowledge = ingredientKnowledge
        let chosen = alchemySelection ?? []
        return runtime.inventory.inventory(of: runtime.player).stacks
            .reduce(into: [FormID: Int32]()) { $0[$1.item, default: 0] += $1.count }
            .compactMap { item, count -> AlchemyIngredientReadout? in
                guard let ingredient = items.ingredients[item.rawValue] else { return nil }
                return AlchemyIngredientReadout(
                    id: item,
                    name: name(of: item),
                    count: count,
                    effects: ingredient.effects.indices.map { index in
                        knowledge.knows(index, of: item)
                            ? effectName(ingredient.effects[index].effect) : nil
                    },
                    isChosen: chosen.contains(item)
                )
            }
            .sorted { $0.name < $1.name }
    }

    /// Adds `item` to the chosen ingredients, or takes it out when already chosen.
    @discardableResult
    public func toggleAlchemyIngredient(_ item: FormID) -> AlchemyActionOutcome {
        guard let runtime else { return noteAlchemy(.unavailable) }
        guard var chosen = alchemySelection else { return noteAlchemy(.noLab) }
        let itemName = name(of: item)
        if let index = chosen.firstIndex(of: item) {
            chosen.remove(at: index)
            alchemySelection = chosen
            return noteAlchemy(.dropped(itemName, preview: previewText))
        }
        guard runtime.inventory.baselines.items.ingredients[item.rawValue] != nil else {
            return noteAlchemy(.notAnIngredient(itemName))
        }
        guard runtime.inventory.count(of: item, in: runtime.player) > 0 else {
            return noteAlchemy(.noneCarried(itemName))
        }
        guard chosen.count < Self.alchemyIngredientLimit else {
            return noteAlchemy(.tooMany(limit: Self.alchemyIngredientLimit))
        }
        chosen.append(item)
        alchemySelection = chosen
        return noteAlchemy(.picked(itemName, preview: previewText))
    }

    @discardableResult
    public func clearAlchemyIngredients() -> AlchemyActionOutcome {
        guard alchemySelection != nil else { return noteAlchemy(.noLab) }
        alchemySelection = []
        return noteAlchemy(.cleared)
    }

    /// What the chosen ingredients make now. Nil with fewer than two chosen.
    public var alchemyPreview: AlchemyPreview? {
        guard let chosen = alchemySelection, chosen.count >= 2 else { return nil }
        guard let brew = brew(chosen) else {
            return AlchemyPreview(name: nil, value: 0, effects: [])
        }
        return AlchemyPreview(
            name: brewName(brew),
            value: brew.value,
            effects: brew.effects.map { effect in
                "\(effectName(effect.result.effect)) \(Int(effect.result.magnitude))"
                    + " for \(effect.result.duration) s"
            }
        )
    }

    private var previewText: String {
        alchemyPreview?.text ?? AlchemyActionOutcome.needsTwo.text
    }

    /// Uses one of each chosen ingredient. A brew with no shared effect still uses
    /// them up and gives the failed skill use.
    @discardableResult
    public func brewChosenIngredients() -> AlchemyActionOutcome {
        guard let runtime else { return noteAlchemy(.unavailable) }
        guard let chosen = alchemySelection else { return noteAlchemy(.noLab) }
        guard chosen.count >= 2 else { return noteAlchemy(.needsTwo) }
        let consumed = chosen.map { InventoryStack(item: $0, count: 1) }
        guard let brew = brew(chosen), let strongest = brew.primary else {
            do {
                try runtime.inventory.apply(
                    removing: consumed, adding: [], on: runtime.player, usingUp: true
                )
            } catch {
                return noteAlchemy(.brewFailed(reason: String(describing: error)))
            }
            keepCarried(chosen)
            reportAlchemySkillUse(alchemySettings.failedSkillUse)
            return noteAlchemy(.failed(alchemyTexts.failed))
        }
        let (state, potion) = createdPotions.adding(
            name: alchemyTexts.name(
                isPoison: brew.isPoison, effect: effectName(strongest.result.effect)
            ),
            isPoison: brew.isPoison,
            value: brew.value,
            effects: brew.createdEffects
        )
        let count = potionsCreated(of: potion)
        do {
            runtime.inventory.baselines.items.registerCreated(potion.ingestible)
            try runtime.inventory.apply(
                removing: consumed,
                adding: [InventoryStack(item: potion.id, count: count)],
                on: runtime.player,
                usingUp: true
            )
        } catch {
            return noteAlchemy(.brewFailed(reason: String(describing: error)))
        }
        runtime.store.set(state, for: .player)
        learn(brew.learned)
        reportAlchemySkillUse(brew.skillValue)
        keepCarried(chosen)
        return noteAlchemy(.brewed(count: count, item: potion.name, value: potion.value))
    }

    // MARK: - Learning

    /// Eating teaches the first effect, or more with Experimenter (Mod Initial
    /// Ingredient Effects Learned).
    @discardableResult
    public func learnEatenIngredient(_ item: FormID) -> AlchemyActionOutcome {
        guard let ingredient = runtime?.inventory.baselines.items.ingredients[item.rawValue] else {
            return noteAlchemy(.notAnIngredient(name(of: item)))
        }
        let count = world.perkModified(
            1,
            at: .modInitialIngredientEffectsLearned,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player),
            seams: ConditionContext()
        )
        let learnt = count.isFinite ? max(1, Int(count.rounded(.down))) : 1
        let before = Set(ingredientKnowledge.knownIndices(of: item))
        let indices = Array(ingredient.effects.indices.prefix(learnt))
        learn([item: indices])
        let names = indices.filter { !before.contains($0) }
            .map { effectName(ingredient.effects[$0].effect) }
        return noteAlchemy(.learned(ingredient: name(of: item), effects: names))
    }

    func learn(_ learned: [FormID: [Int]]) {
        guard let runtime, !learned.isEmpty else { return }
        var knowledge = ingredientKnowledge
        for (ingredient, indices) in learned {
            knowledge = knowledge.learning(indices, of: ingredient)
        }
        runtime.store.set(knowledge, for: .player)
    }

    // MARK: - Rules glue

    func brew(_ chosen: [FormID]) -> AlchemyBrew? {
        guard let items = runtime?.inventory.baselines.items, let store = magicEffects else {
            return nil
        }
        let plugin = magicItemPlugin
        let ingredients = chosen.compactMap { item in
            items.ingredients[item.rawValue].map {
                AlchemyIngredient(id: item, effects: $0.effects)
            }
        }
        let skill = recipeConditions?.skillLevel(at: Self.alchemySkill) ?? 0
        return AlchemyRules.brew(
            ingredients,
            resolve: { store.resolve($0, fromPlugin: plugin) },
            power: AlchemyRules.powerFactor(skill: skill, settings: alchemySettings),
            perks: alchemyPerks
        )
    }

    private var alchemyPerks: AlchemyPerks {
        let world = world
        return AlchemyPerks(
            effectiveness: { effect, isPoison in
                var seams = ConditionContext()
                seams.alchemy = AlchemyConditionResolution(isPoison: isPoison, effect: effect)
                let value = world.perkModified(
                    1,
                    at: .modAlchemyEffectiveness,
                    on: .player,
                    subjects: PerkEvaluationSubjects(owner: .player),
                    seams: seams
                )
                return value.isFinite ? max(0, value) : 1
            },
            purifies: world.perkModified(
                0,
                at: .purifyAlchemyIngredients,
                on: .player,
                subjects: PerkEvaluationSubjects(owner: .player),
                seams: ConditionContext()
            ) > 0
        )
    }

    private func brewName(_ brew: AlchemyBrew) -> String? {
        brew.primary.map {
            alchemyTexts.name(isPoison: brew.isPoison, effect: effectName($0.result.effect))
        }
    }

    /// Mod Potions Created, with the made potion bound as the item.
    private func potionsCreated(of potion: CreatedPotion) -> Int32 {
        let subject = runtime?.inventory.baselines.items.conditionSubject(of: potion.id)
        let value = world.perkModified(
            1,
            at: .modPotionsCreated,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player).binding(.item, to: subject),
            seams: ConditionContext()
        )
        return value.isFinite ? Int32(clamping: Int(max(1, value.rounded(.down)))) : 1
    }

    /// The MGEF's display name in the load order's language.
    func effectName(_ effect: FormID) -> String {
        guard let resolved = magicEffects?.resolve(effect, fromPlugin: magicItemPlugin) else {
            return effect.description
        }
        return world.magicEffectName(resolved)
    }

    /// Keeps chosen only the ingredients the player still carries.
    private func keepCarried(_ chosen: [FormID]) {
        guard let runtime else { return }
        alchemySelection = chosen.filter { runtime.inventory.count(of: $0, in: runtime.player) > 0 }
    }

    private func reportAlchemySkillUse(_ amount: Float) {
        guard amount > 0, let skillUses else { return }
        _ = skillUses.reportSkillUse(SkillUseEvent(
            actor: .player, action: .craft(skill: Self.alchemySkill), amount: amount
        ))
    }

    @discardableResult
    func noteAlchemy(_ outcome: AlchemyActionOutcome) -> AlchemyActionOutcome {
        lastAlchemy = outcome
        return outcome
    }
}

// MARK: - Scripts

extension InventoryCoordinator {
    /// `Ingredient.LearnEffect` and `LearnAllEffects`: nil `indices` teaches every effect.
    /// False when `item` is no ingredient.
    @discardableResult
    public func learnIngredientEffects(_ item: FormID, indices: [Int]?) -> Bool {
        guard let ingredient = runtime?.inventory.baselines.items.ingredients[item.rawValue] else {
            return false
        }
        let all = Array(ingredient.effects.indices)
        learn([item: indices.map { $0.filter(all.contains) } ?? all])
        return true
    }

    /// `Ingredient.LearnNextEffect`: the index learnt, -1 when every effect is known,
    /// nil when `item` is no ingredient.
    public func learnNextIngredientEffect(_ item: FormID) -> Int? {
        guard let ingredient = runtime?.inventory.baselines.items.ingredients[item.rawValue] else {
            return nil
        }
        let knowledge = ingredientKnowledge
        guard
            let next = ingredient.effects.indices.first(where: {
                !knowledge.knows($0, of: item)
            }) else { return -1 }
        learn([item: [next]])
        return next
    }

    /// `IsHostile` on a potion or an ingredient: a potion by its Poison flag, an
    /// ingredient by its costliest effect, as a brew decides. Nil for anything else.
    public func isHostileItem(_ item: FormID) -> Bool? {
        guard let items = runtime?.inventory.baselines.items else { return nil }
        if let potion = items.ingestibles[item.rawValue] {
            return potion.flags.contains(.poison)
        }
        guard let ingredient = items.ingredients[item.rawValue], let store = magicEffects else {
            return nil
        }
        let plugin = magicItemPlugin
        let costliest = ingredient.effects.compactMap { entry -> (Float, Bool)? in
            store.resolve(entry.effect, fromPlugin: plugin).map { effect in
                let result = AlchemyRules.scaled(entry, effect, power: 1)
                return (AlchemyRules.cost(of: result, effect), AlchemyRules.isHostile(effect))
            }
        }.max { $0.0 < $1.0 }
        return costliest?.1 ?? false
    }
}
