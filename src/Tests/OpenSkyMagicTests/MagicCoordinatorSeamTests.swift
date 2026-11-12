// What the adapters ask of the magic shell: perk abilities, dispels, the magic menu,
// and a held staff. Records are synthetic and built in code.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFeaturesTesting
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import OpenSkyInventoryInterface
@testable import OpenSkyMagic
import OpenSkyMagicFixtures
@testable import OpenSkyMagicInterface
import OpenSkyProgressionInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct MagicCoordinatorSeamTests {
    /// A player that owns no perk.
    private struct NoPerks: PerkAccess {
        var perks = PerkStore(plugins: [])
        var conditions = ConditionContext()

        func owns(_: ReferenceKey, on _: ActorValueHolder) -> Bool {
            false
        }

        func ownedPerks(of _: ActorValueHolder) -> [ResolvedPerk] {
            []
        }

        mutating func modify(
            _ value: Float,
            at _: PerkEntryPoint,
            on _: ActorValueHolder,
            reading _: PerkInputs
        ) -> PerkEntryPointOutcome {
            PerkEntryPointOutcome(value: value, input: value, applied: 0, skipped: [])
        }
    }

    /// Perk abilities need both the caster's spells and the effect runtime.
    @Test func perkAbilitiesReconcileOnlyWithCastingAndEffectsWired() throws {
        let holder = ActorValueHolder.player
        #expect(!MagicCoordinator(world: FakeMagicWorld())
            .itemUse.reconcilePerkAbilities(on: holder, perks: NoPerks()))
        #expect(try !MagicCoordinatorTests.effectsWired(FakeMagicWorld())
            .itemUse.reconcilePerkAbilities(on: holder, perks: NoPerks()))
        let file = try ActiveEffectFixture.plugin(records: ActiveEffectFixture.effectRecords)
        var data = MagicSessionData()
        data.effects = MagicEffectsData(
            values: FixedActorValues(),
            store: MagicEffectStore(plugins: [(ActiveEffectFixture.pluginName, file)]),
            pluginName: ActiveEffectFixture.pluginName,
            conditionRegistry: ConditionFunctionRegistry()
        )
        data.casting = try MagicCastingData(
            spellbook: SpellbookFixture.runtime().0,
            values: FixedActorValues(),
            spellPluginName: SpellbookFixture.pluginName,
            baselines: nil
        )
        let wired = MagicCoordinator(world: FakeMagicWorld(), data: data)
        #expect(wired.itemUse.reconcilePerkAbilities(on: holder, perks: NoPerks()))
    }

    @Test func dispellingByPredicateCountsNothingWithoutEffects() throws {
        let holder = ActorValueHolder.player
        #expect(MagicCoordinator(world: FakeMagicWorld()).itemUse.dispelEffects(on: holder) { _ in
            true
        } == 0)
        let wired = try MagicCoordinatorTests.effectsWired(FakeMagicWorld())
        #expect(wired.itemUse.dispelEffects(on: holder) { _ in true } == 0)
    }

    /// Without a wired equipment seam, no hand holds a staff.
    @Test func aHeldStaffPairsAStaffEnchantmentWithItsSpell() throws {
        let coordinator = try MagicCoordinatorTests.castingWired(FakeMagicWorld())
        #expect(coordinator.heldStaves.heldStaff(of: .player, in: .right) == nil)
        let caster = try #require(coordinator.caster)
        caster.spellbook.grant([SpellbookFixture.key(SpellbookFixture.Spell.healing)], to: .player)
        let spell = try #require(coordinator.controlPanels.playerKnownSpells().first)
        let profile = ItemEnchantmentProfile(
            item: FormID(0x800), enchantment: .plugin(name: "base.esm", objectID: 0x801),
            sourcePlugin: "Base.esm", entries: [], name: "Staff of Healing",
            castingType: .fireAndForget, delivery: .touch, type: .staffEnchantment,
            capacity: 100, costPerUse: 10, wornRestriction: nil
        )
        let staff = HeldStaff(profile: profile, spell: spell)
        #expect(staff.profile.isStaff)
        #expect(staff.spell.displayName == spell.displayName)
    }
}
