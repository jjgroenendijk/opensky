// Main-app crafting and harvest seam: the open station's recipes with their
// verdicts, the station list, and the crosshair plant. AppKit-free.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldInterface

/// One recipe row: what it makes and whether the player can make it now.
nonisolated public struct CraftingRecipeReadout: Equatable, Sendable {
    public let id: ResolvedFormID
    public let name: String
    /// `ready`, or what stops it, such as `needs HasPerk`.
    public let verdict: String
    public let isEligible: Bool

    public init(id: ResolvedFormID, name: String, verdict: String, isEligible: Bool) {
        self.id = id
        self.name = name
        self.verdict = verdict
        self.isEligible = isEligible
    }

    public var line: String {
        "\(name): \(verdict)"
    }
}

/// The crosshair plant, when the crosshair is on one.
nonisolated public struct HarvestTargetReadout: Equatable, Sendable {
    public let name: String
    public let produce: String
    public let isHarvested: Bool
    /// Game days until it grows back. Nil when not harvested, or when the
    /// harvest time is unknown.
    public let daysUntilRegrowth: Float?

    public init(name: String, produce: String, isHarvested: Bool, daysUntilRegrowth: Float? = nil) {
        self.name = name
        self.produce = produce
        self.isHarvested = isHarvested
        self.daysUntilRegrowth = daysUntilRegrowth
    }

    /// The regrowth line of the readout.
    public var regrowthText: String {
        guard isHarvested else { return "Grows back: -" }
        guard let days = daysUntilRegrowth else { return "Grows back: never (time unknown)" }
        return "Grows back: in \(String(format: "%.1f", days)) game days"
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

@MainActor
public protocol CraftingControlProviding: AnyObject {
    var craftingSnapshot: CraftingControlSnapshot { get }
    @discardableResult
    func openCraftingStation(_ editorID: String) -> String
    @discardableResult
    func craftRecipe(_ id: ResolvedFormID) -> String
    @discardableResult
    func closeCraftingStation() -> String
    @discardableResult
    func forceHarvest() -> String
    @discardableResult
    func resetHarvest() -> String
}

extension InventoryCoordinator: CraftingControlProviding {
    public var craftingSnapshot: CraftingControlSnapshot {
        guard runtime != nil else { return .unavailable }
        return CraftingControlSnapshot(
            isAvailable: true,
            stationName: crafting?.interaction.name,
            skillName: crafting?.station.skill.flatMap(ActorValueIdentity.name(at:)),
            recipes: crafting?.statuses.map(recipeReadout) ?? [],
            stations: craftingCatalog?.stations.map(\.editorID) ?? [],
            harvestTarget: harvestTarget(),
            lastCraftText: lastCraftText,
            lastActionText: lastActionText
        )
    }

    public func openCraftingStation(_ editorID: String) -> String {
        openCraftingSession(station: editorID)
    }

    public func craftRecipe(_ id: ResolvedFormID) -> String {
        craft(id)
    }

    public func closeCraftingStation() -> String {
        closeCraftingSession()
    }

    public func forceHarvest() -> String {
        harvestInteractionTarget()
    }

    public func resetHarvest() -> String {
        resetHarvestOfInteractionTarget()
    }

    private func harvestTarget() -> HarvestTargetReadout? {
        guard let interaction = world?.crosshairInteraction, interaction.action == .harvest
        else { return nil }
        let day = world?.gameDaysPassed
        let isHarvested = runtime?.isHarvested(interaction, onDay: day) ?? false
        var daysLeft: Float?
        if isHarvested, let day, let regrowth = runtime?.regrowthDay(of: interaction) {
            daysLeft = max(0, regrowth - day)
        }
        return HarvestTargetReadout(
            name: interaction.name,
            produce: interaction.produce?.ingredient.map(name(of:)) ?? "none",
            isHarvested: isHarvested,
            daysUntilRegrowth: daysLeft
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
                isEligible: status.isReady
            )
        }
        let copies = temper.copies.map(Tempering.name(level:)).joined(separator: ", ")
        return CraftingRecipeReadout(
            id: recipe.id,
            name: "\(itemName) (\(copies))",
            verdict: temperVerdict(status, temper),
            isEligible: status.isReady
        )
    }

    private func temperVerdict(_ status: CraftingRecipeStatus, _ temper: TemperTarget) -> String {
        guard let from = temper.from else {
            return "best quality for this skill (\(Tempering.name(level: temper.maximum)))"
        }
        guard status.eligibility.isEligible else { return verdict(status.eligibility) }
        let step = "\(Tempering.name(level: from)) -> \(Tempering.name(level: temper.maximum))"
        return temperStat(temper.item, from: from, to: temper.maximum).map {
            "ready: \(step), \($0)"
        } ?? "ready: \(step)"
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
            return "needs \(function)"
        }
        let missing = eligibility.shortfalls.map {
            "\(name(of: $0.item)) \($0.held) of \($0.required)"
        }
        return "missing " + missing.joined(separator: ", ")
    }
}

/// The section readouts, kept here so a package test can pin them.
nonisolated public enum CraftingReadout {
    /// Recipe rows past this many are counted, not listed.
    public static let listedRecipes = 12

    public static func craftingText(for snapshot: CraftingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return snapshot.lastActionText }
        guard let station = snapshot.stationName else {
            return ["Station: none", "Last: \(snapshot.lastCraftText)"].joined(separator: "\n")
        }
        let ready = snapshot.recipes.count(where: \.isEligible)
        var lines = [
            "Station: \(station)",
            "Skill: \(snapshot.skillName ?? "none")",
            "Recipes: \(snapshot.recipes.count), ready \(ready)"
        ]
        lines += snapshot.recipes.prefix(listedRecipes).map { "  \($0.line)" }
        if snapshot.recipes.count > listedRecipes {
            lines.append("  and \(snapshot.recipes.count - listedRecipes) more")
        }
        lines.append("Last: \(snapshot.lastCraftText)")
        return lines.joined(separator: "\n")
    }

    public static func harvestText(for snapshot: CraftingControlSnapshot) -> String {
        guard snapshot.isAvailable else { return snapshot.lastActionText }
        guard let target = snapshot.harvestTarget else {
            return ["Plant: none", "Last: \(snapshot.lastActionText)"].joined(separator: "\n")
        }
        return [
            "Plant: \(target.name)",
            "Produce: \(target.produce)",
            "Harvested: \(target.isHarvested ? "yes" : "no")",
            target.regrowthText,
            "Last: \(snapshot.lastActionText)"
        ].joined(separator: "\n")
    }
}
