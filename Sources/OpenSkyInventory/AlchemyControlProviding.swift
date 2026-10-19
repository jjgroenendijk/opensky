// The sidebar seam for alchemy: open a lab, choose ingredients, preview and brew,
// eat an ingredient to learn its effect, and put a poison on the drawn weapon.
// See docs/engine/alchemy.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface

/// One carried poison.
nonisolated public struct AlchemyPoisonReadout: Equatable, Sendable {
    public let id: FormID
    public let name: String
    public let count: Int32

    public init(id: FormID, name: String, count: Int32) {
        self.id = id
        self.name = name
        self.count = count
    }
}

nonisolated public struct AlchemyControlSnapshot: Equatable, Sendable {
    public static let unavailable = AlchemyControlSnapshot(
        isAvailable: false, labName: nil, labs: [], ingredients: [], poisons: [],
        previewText: "", weaponPoisonText: "", brewedCount: 0, knownEffectCount: 0,
        lastActionText: AlchemyActionOutcome.unavailable.text
    )

    public let isAvailable: Bool
    /// The open lab, or nil when none is open.
    public let labName: String?
    /// Every alchemy lab base, by editor ID, for opening one without walking there.
    public let labs: [String]
    public let ingredients: [AlchemyIngredientReadout]
    public let poisons: [AlchemyPoisonReadout]
    public let previewText: String
    public let weaponPoisonText: String
    /// How many different potions this game has brewed.
    public let brewedCount: Int
    public let knownEffectCount: Int
    public let lastActionText: String

    public init(
        isAvailable: Bool, labName: String?, labs: [String],
        ingredients: [AlchemyIngredientReadout], poisons: [AlchemyPoisonReadout],
        previewText: String, weaponPoisonText: String, brewedCount: Int,
        knownEffectCount: Int, lastActionText: String
    ) {
        self.isAvailable = isAvailable
        self.labName = labName
        self.labs = labs
        self.ingredients = ingredients
        self.poisons = poisons
        self.previewText = previewText
        self.weaponPoisonText = weaponPoisonText
        self.brewedCount = brewedCount
        self.knownEffectCount = knownEffectCount
        self.lastActionText = lastActionText
    }

    public var readoutText: String {
        guard isAvailable else { return lastActionText }
        let chosen = ingredients.filter(\.isChosen).map(\.name)
        return [
            "Lab: \(labName ?? "none open")",
            "Chosen: \(chosen.isEmpty ? "none" : chosen.joined(separator: ", "))",
            previewText.isEmpty ? nil : "Brew: \(previewText)",
            "Known effects: \(knownEffectCount)   Potions brewed: \(brewedCount)",
            "Weapon poison: \(weaponPoisonText)",
            "Last: \(lastActionText)"
        ].compactMap(\.self).joined(separator: "\n")
    }
}

@MainActor
public protocol AlchemyControlProviding: AnyObject {
    var alchemySnapshot: AlchemyControlSnapshot { get }
    @discardableResult
    func openAlchemyLab(_ editorID: String) -> CraftingActionOutcome
    @discardableResult
    func toggleAlchemyIngredient(_ id: FormID) -> AlchemyActionOutcome
    @discardableResult
    func clearAlchemyIngredients() -> AlchemyActionOutcome
    @discardableResult
    func brewChosenIngredients() -> AlchemyActionOutcome
    /// Eats one `id`, which applies its effects and teaches the first. The learnt
    /// effects reach the snapshot's last action.
    func eatIngredient(_ id: FormID)
    @discardableResult
    func applyPoison(_ id: FormID) -> AlchemyActionOutcome
}

extension InventoryCoordinator {
    public var alchemySnapshot: AlchemyControlSnapshot {
        guard let runtime else { return .unavailable }
        let held = runtime.inventory.inventory(of: runtime.player).stacks
            .reduce(into: [FormID: Int32]()) { $0[$1.item, default: 0] += $1.count }
        return AlchemyControlSnapshot(
            isAvailable: magicEffects != nil,
            labName: alchemySelection == nil ? nil : crafting?.interaction.name,
            labs: alchemyLabs,
            ingredients: alchemyIngredients,
            poisons: held.filter { isPoison($0.key) }
                .map { item, count in
                    AlchemyPoisonReadout(id: item, name: name(of: item), count: count)
                }
                .sorted { $0.name < $1.name },
            previewText: alchemySelection == nil ? "" : (alchemyPreview?.text ?? "choose two"),
            weaponPoisonText: weaponPoisonText,
            brewedCount: createdPotions.potions.count,
            knownEffectCount: ingredientKnowledge.known.values
                .reduce(0) { $0 + $1.nonzeroBitCount },
            lastActionText: lastAlchemy.text
        )
    }

    /// Every lab base the catalog lists.
    public var alchemyLabs: [String] {
        craftingCatalog?.stations.filter {
            [.alchemy, .alchemyExperiment].contains($0.workbench.benchType)
        }.map(\.editorID) ?? []
    }

    @discardableResult
    public func openAlchemyLab(_ editorID: String) -> CraftingActionOutcome {
        openCraftingSession(station: editorID)
    }

    private var weaponPoisonText: String {
        let poisons = playerWeaponPoisons.poisons.sorted { $0.key.rawValue < $1.key.rawValue }
        guard !poisons.isEmpty else { return "none" }
        return poisons.map { weapon, poison in
            "\(name(of: poison.poison)) on \(name(of: weapon)), \(poison.doses) hit(s)"
        }.joined(separator: "; ")
    }
}
