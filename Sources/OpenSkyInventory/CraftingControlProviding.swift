// Main-app crafting and harvest seam: the open station's recipes with their
// verdicts, the station list, and the crosshair plant. AppKit-free.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

/// One recipe row: what it makes and whether the player can make it now.
nonisolated public struct CraftingRecipeReadout: Equatable, Sendable {
    public let id: ResolvedFormID
    public let name: String
    /// `ready`, or what stops it, such as `needs HasPerk`.
    public let verdict: String
    public let isEligible: Bool
    /// False when a condition fails, so the crafting menu leaves the recipe out.
    public let isOffered: Bool

    public init(
        id: ResolvedFormID, name: String, verdict: String, isEligible: Bool, isOffered: Bool = true
    ) {
        self.id = id
        self.name = name
        self.verdict = verdict
        self.isEligible = isEligible
        self.isOffered = isOffered
    }

    public var line: String {
        "\(name): \(verdict)"
    }
}

/// This season and its `PFPC` chance; a nil chance always yields.
nonisolated public struct HarvestSeasonChance: Equatable, Sendable {
    public let season: HarvestSeason
    public let chance: Float?

    public init(season: HarvestSeason, chance: Float?) {
        self.season = season
        self.chance = chance
    }
}

/// The crosshair plant, when the crosshair is on one.
nonisolated public struct HarvestTargetReadout: Equatable, Sendable {
    public let name: String
    public let produce: String
    public let isHarvested: Bool
    /// Game days away from its cell before the cell resets. Nil when not harvested.
    public let resetDays: Float?
    /// This season and its `PFPC` chance; a nil chance always yields. Nil without a clock.
    public let seasonChance: HarvestSeasonChance?

    public init(
        name: String,
        produce: String,
        isHarvested: Bool,
        resetDays: Float? = nil,
        seasonChance: HarvestSeasonChance? = nil
    ) {
        self.name = name
        self.produce = produce
        self.isHarvested = isHarvested
        self.resetDays = resetDays
        self.seasonChance = seasonChance
    }

    /// The regrowth line of the readout.
    public var regrowthText: String {
        guard isHarvested else { return "Grows back: -" }
        guard let days = resetDays else { return "Grows back: when its cell resets" }
        return "Grows back: when its cell resets, \(String(format: "%.1f", days)) game days"
            + " after you leave it"
    }

    /// The yield line: this season and its chance.
    public var seasonText: String {
        guard let seasonChance else { return "Season: unknown (always yields)" }
        let chance = seasonChance.chance.map { String(format: "%.0f%%", $0) } ?? "always"
        return "Season: \(seasonChance.season), yields \(chance)"
    }
}

nonisolated public struct CraftingControlSnapshot: Equatable, Sendable {
    public let isAvailable: Bool
    public let stationName: String?
    public let skillName: String?
    public let recipes: [CraftingRecipeReadout]
    /// Station editor IDs the dev control can open.
    public let stations: [String]
    public let harvestTarget: HarvestTargetReadout?
    public let lastCraftText: String
    public let lastActionText: String

    public static let unavailable = CraftingControlSnapshot(
        isAvailable: false, stationName: nil, skillName: nil, recipes: [], stations: [],
        harvestTarget: nil, lastCraftText: "No recipe data.", lastActionText: "No item runtime."
    )

    public init(
        isAvailable: Bool,
        stationName: String?,
        skillName: String?,
        recipes: [CraftingRecipeReadout],
        stations: [String],
        harvestTarget: HarvestTargetReadout?,
        lastCraftText: String,
        lastActionText: String
    ) {
        self.isAvailable = isAvailable
        self.stationName = stationName
        self.skillName = skillName
        self.recipes = recipes
        self.stations = stations
        self.harvestTarget = harvestTarget
        self.lastCraftText = lastCraftText
        self.lastActionText = lastActionText
    }
}

extension InventoryCoordinator {
    public var craftingSnapshot: CraftingControlSnapshot {
        guard runtime != nil else { return .unavailable }
        return CraftingControlSnapshot(
            isAvailable: true,
            stationName: crafting?.interaction.name,
            skillName: crafting?.station.skill.flatMap(ActorValueIdentity.name(at:)),
            recipes: crafting?.statuses.map(recipeReadout) ?? [],
            stations: craftingCatalog?.stations.map(\.editorID) ?? [],
            harvestTarget: harvestTarget(),
            lastCraftText: lastCraft.text,
            lastActionText: lastAction.text
        )
    }

    private func harvestTarget() -> HarvestTargetReadout? {
        guard let interaction = world.crosshairInteraction, interaction.action == .harvest
        else { return nil }
        let isHarvested = runtime?.isHarvested(interaction) ?? false
        let season = harvestMoment.season
        return HarvestTargetReadout(
            name: interaction.name,
            produce: interaction.produce?.ingredient.map(name(of:)) ?? "none",
            isHarvested: isHarvested,
            resetDays: isHarvested ? Float(cellReset.hours) / 24 : nil,
            seasonChance: season.map {
                HarvestSeasonChance(
                    season: $0, chance: $0.chance(in: interaction.produce?.seasonalChance)
                )
            }
        )
    }

    private func recipeReadout(_ status: CraftingRecipeStatus) -> CraftingRecipeReadout {
        let recipe = status.recipe
        let itemName = recipe.created.map(name(of:)) ?? recipe.editorID ?? recipe.id.description
        guard let temper = status.temper else {
            return CraftingRecipeReadout(
                id: recipe.id,
                name: itemName,
                verdict: verdict(status.eligibility),
                isEligible: status.isReady,
                isOffered: status.eligibility.isOffered
            )
        }
        let copies = temper.copies.map { qualityName($0, of: temper.item) }
            .joined(separator: ", ")
        return CraftingRecipeReadout(
            id: recipe.id,
            name: "\(itemName) (\(copies))",
            verdict: temperVerdict(status, temper),
            isEligible: status.isReady,
            isOffered: status.eligibility.isOffered
        )
    }

    private func temperVerdict(_ status: CraftingRecipeStatus, _ temper: TemperTarget) -> String {
        guard let from = temper.from else {
            return "best quality for this skill (\(qualityName(temper.maximum, of: temper.item)))"
        }
        guard status.eligibility.isEligible else { return verdict(status.eligibility) }
        let step = "\(qualityName(from, of: temper.item)) -> "
            + qualityName(temper.maximum, of: temper.item)
        return temperStat(temper.item, from: from, to: temper.maximum).map {
            "ready: \(step), \($0)"
        } ?? "ready: \(step)"
    }

    /// The quality name of `level`, from the weapon or the armour list.
    func qualityName(_ level: Int32, of item: FormID) -> String {
        let isWeapon = runtime?.inventory.baselines.items.weapon(item) != nil
        return temperingTexts.name(level: level, isWeapon: isWeapon)
    }

    /// Damage for a weapon, armor rating for armor, before and after the temper.
    func temperStat(_ item: FormID, from: Int32, to: Int32) -> String? {
        guard let items = runtime?.inventory.baselines.items else { return nil }
        let base: Float
        let label: String
        var isBody = false
        if let weapon = items.weapon(item) {
            (base, label) = (Float(weapon.damage), "damage")
        } else if let armor = items.armor[item.rawValue] {
            (base, label) = (Float(armor.armorRating & 0xFFFF) / 100, "rating")
            isBody = armor.bodyTemplate?.slots.contains(.body) ?? false
        } else {
            return nil
        }
        let before = base + Tempering.bonus(level: from, isBodyArmor: isBody)
        let after = base + Tempering.bonus(level: to, isBodyArmor: isBody)
        return String(format: "%@ %.1f -> %.1f", label, before, after)
    }

    private func verdict(_ eligibility: RecipeEligibility) -> String {
        if eligibility.isEligible {
            return "ready"
        }
        if eligibility.hasUnresolvedItem {
            return "item not loaded"
        }
        if let function = eligibility.failingFunction {
            return "hidden: needs \(function)"
        }
        let missing = eligibility.shortfalls.map {
            "\(name(of: $0.item)) \($0.held) of \($0.required)"
        }
        return "missing " + missing.joined(separator: ", ")
    }
}
