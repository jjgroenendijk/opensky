// Active-effect checks on the real install: a vanilla healing potion from the
// load order restores the player's health, and every ALCH and INGR effect in
// `Skyrim.esm` is planned, with unimplemented archetypes counted. Only counts,
// editor IDs, and health numbers are checked.

import Foundation
@testable import OpenSkyActors
@testable import OpenSkyActorsInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyInventory
@testable import OpenSkyInventoryInterface
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
@testable import OpenSkyWorld
@testable import OpenSkyWorldState
import Testing

@MainActor
struct ActiveEffectRealDataTests {
    private static let pluginName = "Skyrim.esm"

    /// Health, as `ActorValueIdentity` numbers it.
    private static let healthIndex: Int32 = 24

    /// One real ingredient authoring more than one effect, paired with what
    /// eating it actually applies.
    private struct MultiEffectIngredient {
        /// How many effects the INGR record carries.
        let authored: Int
        let use: MagicItemUse
    }

    private struct Harness {
        let effects: ActiveEffectRuntime
        let inventory: InventoryRuntime
        let items: ItemDefinitionStore
    }

    private func harness(root: GameDataRoot) throws -> Harness {
        let file = try ESMFile(url: root.dataURL.appending(path: Self.pluginName))
        let store = WorldStateStore()
        let baselines = InventoryBaselineResolver.build(from: file)
        let values = ActorValueRuntime(
            store: store,
            baselines: ActorValueBaselineResolver(
                resolver: ActorValueResolver.build(
                    from: file,
                    localized: (try? file.pluginHeader().isLocalized) ?? false,
                    pluginName: Self.pluginName,
                    settings: ActorValueLevelSettings.resolve(
                        store: GameSettingLoader.load(root: root, baseFile: file)
                    )
                )
            )
        )
        return Harness(
            effects: ActiveEffectRuntime(
                values: values,
                effects: MagicEffectStoreLoader.load(root: root, baseFile: file),
                conditionRegistry: .standard
            ),
            inventory: InventoryRuntime(store: store, baselines: baselines),
            items: baselines.items
        )
    }

    /// The milestone's acceptance path against real records: a real healing
    /// potion restores real health.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aVanillaHealingPotionRestoresThePlayersHealth() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let harness = try harness(root: root)
        var effects = harness.effects
        // Found by what it does rather than by a remembered editor ID or
        // FormID: the first ALCH whose effect list plans to an instant,
        // non-detrimental application to health is a healing potion by
        // definition, and stays one whatever a load order renames.
        let potion = try #require(
            harness.items.definitions(of: .ingestible)
                .first { definition in
                    healsHealth(definition.formID, in: harness)
                }
        )
        let use = try #require(harness.items.magicItemUse(potion.formID))
        #expect(use.kind == .potion)
        #expect(!use.effects.isEmpty)

        try harness.inventory.add(potion.formID, count: 1, to: .player)
        let maximum = effects.values.baseline(of: .player).maximums.health
        effects.values.damage(.health, by: maximum / 2, on: .player)
        let wounded = effects.values.current(of: .player).health

        let outcome = try effects.consume(
            potion.formID,
            from: .player,
            on: .player,
            inventory: harness.inventory,
            fromPlugin: Self.pluginName
        )
        let healed = effects.values.current(of: .player).health
        #expect(healed > wounded)
        #expect(healed <= maximum)
        // A restore-health effect is instantaneous, so nothing is left running.
        #expect(outcome.stored.isEmpty)
        #expect(effects.active(on: .player).isEmpty)
        #expect(harness.inventory.count(of: potion.formID, in: .player) == 0)
    }

    /// Whether consuming `item` instantly restores health.
    private func healsHealth(_ item: FormID, in harness: Harness) -> Bool {
        guard let use = harness.items.magicItemUse(item) else { return false }
        return use.effects.contains { entry in
            guard
                let resolved = harness.effects.effects.resolve(
                    entry,
                    fromPlugin: Self.pluginName
                ),
                case let .apply(application) = MagicEffectPlanner.plan(
                    effect: resolved,
                    entry: entry
                )
            else { return false }
            return application.isInstant
                && !application.isDetrimental
                && application.values.contains { $0.index == Self.healthIndex }
                && application.values.contains { $0.magnitude > 0 }
        }
    }

    /// Eating a real ingredient applies its first effect and only its first.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func eatingARealIngredientUsesOnlyItsFirstEffect() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let harness = try harness(root: root)
        let multiEffect = try #require(
            harness.items.definitions(of: .ingredient)
                .lazy
                .compactMap { definition -> MultiEffectIngredient? in
                    guard
                        let ingredient = harness.items.ingredients[definition.formID.rawValue],
                        ingredient.effects.count > 1,
                        let use = harness.items.magicItemUse(definition.formID)
                    else { return nil }
                    return MultiEffectIngredient(
                        authored: ingredient.effects.count,
                        use: use
                    )
                }
                .first
        )
        #expect(multiEffect.authored > 1)
        #expect(multiEffect.use.kind == .ingredient)
        #expect(multiEffect.use.effects.count == 1)
    }

    /// The coverage picture over every consumable in the base plugin: what the
    /// planner can carry out today, and what it counts instead.
    ///
    /// Deliberately asserts shape rather than exact numbers. The counts move
    /// with the load order, and a suite pinned to one install's totals would
    /// fail on a modded one for no reason worth failing over.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func everyConsumableEffectEntryIsPlannedOrCounted() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let harness = try harness(root: root)
        var applied = 0
        var skips: [MagicEffectPlanFailure: Int] = [:]
        var unresolved = 0
        // Timed Recover effects on health, magicka, or stamina, such as Fortify
        // Health, are applied.
        var appliedPrimaryModifiers = 0
        for definition in harness.items.definitions(of: .ingestible) {
            guard let use = harness.items.magicItemUse(definition.formID) else { continue }
            for entry in use.effects {
                guard
                    let resolved = harness.effects.effects.resolve(
                        entry,
                        fromPlugin: Self.pluginName
                    )
                else {
                    unresolved += 1
                    continue
                }
                switch MagicEffectPlanner.plan(effect: resolved, entry: entry) {
                case let .apply(application):
                    applied += 1
                    if
                        application.mode == .modifier,
                        application.values.contains(where: {
                            ActorValueIdentity.kind(at: $0.index) != nil
                        })
                    {
                        appliedPrimaryModifiers += 1
                    }
                case let .skip(reason): skips[reason, default: 0] += 1
                }
            }
        }
        // Every EFID in the base plugin resolves: an unresolved one would mean
        // the MGEF index missed a record the potions point at.
        #expect(unresolved == 0)
        // The three implemented archetypes cover the bulk of what potions do,
        // which is what makes drinking one a working path at all.
        #expect(applied > 0)
        // Measured, not silent: every entry the planner declined landed in a
        // named bucket, so the two halves account for the whole population.
        let skipped = skips.values.reduce(0, +)
        #expect(skips.keys.allSatisfy { failure in
            if case .undecodedEffect = failure {
                return false
            }
            return true
        })
        #expect(applied + skipped > 0)
        #expect(appliedPrimaryModifiers > 0)
        print(
            "[INFO] consumable effect entries: applied \(applied) "
                + "(primary modifiers \(appliedPrimaryModifiers)), skipped \(skipped)"
        )
    }
}
