// The enchantment runtime (issue #472, roadmap item 19.9): a landed hit applying
// its effects and draining charge, an empty weapon applying nothing, and a worn
// item granting constant effects until it comes off.
//
// Records are synthetic and built in code (`EnchantmentRuntimeFixture`) — never
// extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct EnchantmentRuntimeTests {
    private func hit(
        _ profile: ItemEnchantmentProfile,
        target: ActorValueHolder = EnchantmentRuntimeFixture.target
    ) -> WeaponEnchantmentHit {
        WeaponEnchantmentHit(
            profile: profile,
            attacker: .player,
            target: target.key,
            position: .zero
        )
    }

    @discardableResult
    private func land(
        _ profile: ItemEnchantmentProfile,
        in world: inout EnchantmentRuntimeFixture.World
    ) -> WeaponEnchantmentReport {
        WeaponEnchantmentApplication.apply(
            hit(profile),
            owner: .player,
            target: EnchantmentRuntimeFixture.target,
            using: &world.effects
        )
    }

    // MARK: - Resolution

    /// The profile carries what the records say: a weapon enchantment fires on
    /// contact and a worn one does not, and the charge comes off `EAMT` while the
    /// cost comes off `ENIT`.
    @Test func profilesReadTheirShapeOffTheRecords() throws {
        let world = try EnchantmentRuntimeFixture.world()
        let blade = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        #expect(blade.isContact)
        #expect(!blade.isWorn)
        #expect(!blade.isStaff)
        #expect(blade.name == "Burning")
        #expect(blade.capacity == Float(EnchantmentRuntimeFixture.bladeCharge))
        #expect(blade.costPerUse == Float(EnchantmentRuntimeFixture.bladeCostPerUse))
        #expect(blade.fullCharge.usesRemaining == EnchantmentRuntimeFixture.bladeUses)

        let ring = try world.profile(of: EnchantmentRuntimeFixture.enchantedRing)
        #expect(ring.isWorn)
        #expect(!ring.isContact)
        #expect(ring.capacity == 0)

        let plain = try #require(
            world.items.definition(FormID(EnchantmentRuntimeFixture.plainBlade))
        )
        #expect(ItemEnchantmentProfile.resolve(plain, using: world.enchantments) == nil)
    }

    // MARK: - Weapon hits

    /// The scope point: a landed hit applies the enchantment's effects to the
    /// actor it struck and takes one use off the weapon.
    @Test func aLandedHitAppliesTheEffectsAndDrainsOneUse() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let blade = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        let target = EnchantmentRuntimeFixture.target
        #expect(world.effects.values.current(of: target).health == 100)

        let report = land(blade, in: &world)
        #expect(report.didFire)
        #expect(report.entryCount == 1)
        #expect(report.charge.remaining == 72)
        #expect(report.charge.usesRemaining == 4)
        #expect(world.effects.values.current(of: target).health == 95)

        // The charge is per owner and lands in the world-state store, so it
        // survives the runtime being put back and taken out again.
        let ledger = EnchantmentLedger(store: world.store)
        #expect(ledger.charge(of: blade, on: .player).remaining == 72)
    }

    /// A weapon with nothing left applies nothing and says so, rather than firing
    /// on a negative charge or silently skipping the step.
    @Test func anEmptyWeaponStopsApplyingItsEffects() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let blade = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        let target = EnchantmentRuntimeFixture.target
        for _ in 0 ..< EnchantmentRuntimeFixture.bladeUses {
            #expect(land(blade, in: &world).didFire)
        }
        let health = world.effects.values.current(of: target).health
        #expect(health == 100 - EnchantmentRuntimeFixture.bladeDamage * 5)

        let refused = land(blade, in: &world)
        #expect(!refused.didFire)
        #expect(refused.entryCount == 0)
        #expect(refused.charge.remaining == 0)
        #expect(world.effects.values.current(of: target).health == health)
        #expect(refused.describedLine.contains("out of charge"))
    }

    /// A hostile contact effect pays the target's resistances, exactly as a landed
    /// spell's does — the whole reason this applies through `SpellHitApplication`
    /// rather than beside it.
    @Test func aHostileContactEffectPaysTheTargetsResistances() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let blade = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        let target = EnchantmentRuntimeFixture.target
        let resistMagic = try #require(ActorValueIdentity.index(named: "Resist Magic"))
        world.effects.values.setValue(at: resistMagic, to: 50, on: target)

        let report = land(blade, in: &world)
        #expect(report.adjustments.count == 1)
        #expect(report.adjustments.first?.multiplier == 0.5)
        #expect(world.effects.values.current(of: target).health == 97.5)
    }

    /// A target that stopped being resident between the impact and the call still
    /// costs the swing its charge: the blow landed.
    @Test func aHitOnAnAbsentTargetStillSpendsTheCharge() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let blade = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        let report = WeaponEnchantmentApplication.apply(
            hit(blade),
            owner: .player,
            target: nil,
            using: &world.effects
        )
        #expect(report.didFire)
        #expect(report.charge.remaining == 72)
        #expect(report.storedCount == 0)
    }

    /// Recharging is out of scope for this item, but the load path and a dev
    /// control need a way back to full, and it stops recording the item entirely.
    @Test func rechargingForgetsTheStoredCharge() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let blade = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        land(blade, in: &world)
        let ledger = EnchantmentLedger(store: world.store)
        ledger.recharge(blade, on: .player)
        #expect(ledger.charge(of: blade, on: .player).remaining == blade.capacity)
        #expect(world.store.component(EnchantedItemState.self, for: .player) == nil)
    }

    // MARK: - Worn enchantments

    /// The other scope point: putting the ring on grants its constant effect, and
    /// taking it off takes exactly that effect back.
    @Test func wearingAnEnchantedItemGrantsAConstantEffect() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let ring = try world.profile(of: EnchantmentRuntimeFixture.enchantedRing)
        let index = CombatFortifyBonusIndices.oneHanded
        #expect(world.effects.values.value(at: index, on: .player) == 0)

        let applied = WornEnchantmentApplication.reconcile(
            worn: [ring], on: .player, using: &world.effects
        )
        #expect(applied.applied == [FormID(EnchantmentRuntimeFixture.enchantedRing)])
        #expect(applied.storedCount == 1)
        #expect(
            world.effects.values.value(at: index, on: .player)
                == EnchantmentRuntimeFixture.ringFortifyPoints
        )

        let effect = try #require(world.effects.active(on: .player).first)
        #expect(effect.mode == .constant)
        #expect(effect.isConstant)
        #expect(!effect.isExpired)
        #expect(effect.source.kind == .enchantment)

        let removed = WornEnchantmentApplication.removeAll(on: .player, using: &world.effects)
        #expect(removed.removed == [FormID(EnchantmentRuntimeFixture.enchantedRing)])
        #expect(removed.dispelledCount == 1)
        #expect(world.effects.values.value(at: index, on: .player) == 0)
        #expect(world.effects.active(on: .player).isEmpty)
    }

    /// A constant effect is not a timer: sixty seconds of ticking leaves it in
    /// place, which is the whole reason `ActiveEffectMode` grew a third case.
    @Test func aConstantEffectNeverExpiresOnItsOwn() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let ring = try world.profile(of: EnchantmentRuntimeFixture.enchantedRing)
        WornEnchantmentApplication.reconcile(worn: [ring], on: .player, using: &world.effects)
        for _ in 0 ..< 3600 {
            world.effects.step(over: [.player])
        }
        #expect(world.effects.active(on: .player).count == 1)
        #expect(
            world.effects.values.value(at: CombatFortifyBonusIndices.oneHanded, on: .player)
                == EnchantmentRuntimeFixture.ringFortifyPoints
        )
    }

    /// Reconciling is idempotent and does the difference only: a second call with
    /// the same set changes nothing, and swapping one item for another applies one
    /// and removes one.
    @Test func reconcilingIsIdempotentAndAppliesOnlyTheDifference() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let ring = try world.profile(of: EnchantmentRuntimeFixture.enchantedRing)
        let shield = try world.profile(of: EnchantmentRuntimeFixture.enchantedShield)
        WornEnchantmentApplication.reconcile(worn: [ring], on: .player, using: &world.effects)

        let again = WornEnchantmentApplication.reconcile(
            worn: [ring], on: .player, using: &world.effects
        )
        #expect(!again.didChange)
        #expect(world.effects.active(on: .player).count == 1)

        let both = WornEnchantmentApplication.reconcile(
            worn: [ring, shield], on: .player, using: &world.effects
        )
        #expect(both.applied == [FormID(EnchantmentRuntimeFixture.enchantedShield)])
        #expect(both.removed.isEmpty)
        #expect(world.effects.active(on: .player).count == 2)

        let swapped = WornEnchantmentApplication.reconcile(
            worn: [shield], on: .player, using: &world.effects
        )
        #expect(swapped.removed == [FormID(EnchantmentRuntimeFixture.enchantedRing)])
        #expect(swapped.applied.isEmpty)
        #expect(world.effects.values
            .value(at: CombatFortifyBonusIndices.oneHanded, on: .player) == 0)
        #expect(
            world.effects.values.value(at: CombatFortifyBonusIndices.block, on: .player)
                == EnchantmentRuntimeFixture.shieldFortifyPoints
        )
    }

    /// Only a constant effect is worn: handing the reconcile a drawn enchanted
    /// blade applies nothing, so no caller has to know the rule.
    @Test func aContactEnchantmentIsNotWorn() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let blade = try world.profile(of: EnchantmentRuntimeFixture.enchantedBlade)
        let report = WornEnchantmentApplication.reconcile(
            worn: [blade], on: .player, using: &world.effects
        )
        #expect(!report.didChange)
        #expect(world.effects.active(on: .player).isEmpty)
    }

    // MARK: - Worn restriction

    /// The worn restriction is a question, not a gate. It answers correctly for
    /// both items, and applying a worn enchantment does not consult it — because
    /// 70 of the 2,727 restricted vanilla ARMO records fail their own list, which
    /// `EnchantmentRuntimeRealDataTests` pins.
    @Test func theWornRestrictionIsQueryableAndGatesNothingAtRuntime() throws {
        var world = try EnchantmentRuntimeFixture.world()
        let ring = try world.profile(of: EnchantmentRuntimeFixture.enchantedRing)
        let listed = [FormID(EnchantmentRuntimeFixture.ringKeyword)]
        #expect(ring.wornRestriction == FormID(EnchantmentRuntimeFixture.restrictionList))
        #expect(ring.allowsWearing(
            keywords: [FormID(EnchantmentRuntimeFixture.ringKeyword)],
            listedKeywords: listed
        ))
        #expect(!ring.allowsWearing(
            keywords: [FormID(EnchantmentRuntimeFixture.shieldKeyword)],
            listedKeywords: listed
        ))
        // An unresolvable or empty list allows everything, on the same reasoning
        // an unresolvable link elsewhere in this engine is data rather than a fault.
        #expect(ring.allowsWearing(keywords: [], listedKeywords: nil))
        #expect(ring.allowsWearing(keywords: [], listedKeywords: []))

        // The enchantment whose list the item fails still applies, deliberately.
        let report = WornEnchantmentApplication.reconcile(
            worn: [ring], on: .player, using: &world.effects
        )
        #expect(report.storedCount == 1)

        let shield = try world.profile(of: EnchantmentRuntimeFixture.enchantedShield)
        #expect(shield.wornRestriction == nil)
        #expect(shield.allowsWearing(keywords: [], listedKeywords: nil))
    }
}
