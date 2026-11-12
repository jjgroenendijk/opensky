// The session side of soul trap: a death under the effect, or `Actor.TrapSoul`, fills
// the smallest empty gem the player carries. Only the player's gems are filled; an NPC
// caster's trap catches nothing. See docs/engine/soul-trap.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
public import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyWorldState

extension MagicCoordinator.SoulTrapping {
    /// Called once for each death. Soul Siphon feeds the killer's weapon, then the soul
    /// is trapped when a soul trap effect is on the dying actor.
    @discardableResult
    public func noteDeath(
        of victim: ReferenceKey,
        killer: ReferenceKey? = nil
    ) -> SoulTrapOutcome? {
        guard
            let effects = coordinator.effects,
            let holder = coordinator.world.actorValueHolder(for: victim)
        else { return nil }
        if let killer {
            siphonSoul(of: holder, killer: killer)
        }
        let casters = effects.active(on: holder)
            .filter { effects.rule(of: $0) == .world(.soulTrap) }
            .compactMap(\.caster)
        guard let caster = casters.contains(.player) ? .player : casters.first else { return nil }
        return trapSoul(of: victim, by: caster)
    }

    /// `Actor.TrapSoul`: fills a gem the caster carries with `victim`'s soul.
    @discardableResult
    public func trapSoul(of victim: ReferenceKey, by caster: ReferenceKey) -> SoulTrapOutcome {
        guard
            caster == .player,
            let inventory = coordinator.world.inventory,
            let effects = coordinator.effects,
            let holder = coordinator.world.actorValueHolder(for: victim)
        else { return .notFilled }
        let soul = SoulTrap.soul(
            level: effects.values.baseline(of: holder).level,
            isNPC: coordinator.world.actorHasKeyword("ActorTypeNPC", on: holder),
            settings: coordinator.rules.soulTrap
        )
        guard let chosen = SoulTrap.gem(for: soul, among: carriedGems(inventory)) else {
            coordinator.world.postNotification(coordinator.texts.magic.word(
                "sSoulGemTooSmall",
                or: "No soul gem large enough"
            ))
            return .noGem(soul)
        }
        fill(chosen, with: soul, in: inventory)
        coordinator.world.postNotification(coordinator.texts.magic.word(
            "sSoulCaptured",
            or: "Soul captured!"
        ))
        return .trapped(soul, gem: chosen.item)
    }

    /// The player's soul gems, one candidate per held copy.
    func carriedGems(_ inventory: any InventoryAccess) -> [SoulGemCandidate] {
        let gems = inventory.baselines.items.soulGems
        return Set(inventory.inventory(of: .player).stacks.map(\.item))
            .sorted { $0.rawValue < $1.rawValue }
            .flatMap { item -> [SoulGemCandidate] in
                guard let gem = gems[item.rawValue] else { return [] }
                return inventory.copies(of: item, in: .player).map {
                    SoulGemCandidate(item: item, gem: gem, copy: $0)
                }
            }
    }

    /// A gem whose record links a filled one (vanilla: grand and black) becomes that
    /// record, as the game's filled gems stack; any other gem copy keeps the soul itself.
    private func fill(
        _ gem: SoulGemCandidate,
        with soul: TrappedSoul,
        in inventory: any InventoryAccess
    ) {
        if
            let linked = gem.gem.linkedGem,
            Int(soul.size.rawValue) >= gem.capacity,
            attempt({ try inventory.remove(gem.item, count: 1, from: .player) }) != nil
        {
            _ = attempt { try inventory.add(linked, count: 1, to: .player) }
            return
        }
        let size = soul.size.rawValue
        inventory.editCopy(of: gem.item, in: .player, where: { $0 == gem.copy }, { $0.soul = size })
    }
}

extension MagicCoordinator.SoulTrapping {
    /// Soul Siphon: entry point 78 gives the share of `victim`'s soul that goes into
    /// the killer's weapon. The perk's own condition leaves people out.
    @discardableResult
    func siphonSoul(of victim: ActorValueHolder, killer: ReferenceKey) -> EnchantmentCharge? {
        guard
            let runtime = coordinator.effects,
            let items = coordinator.world.inventory?.baselines.items,
            let owner = coordinator.world.actorValueHolder(for: killer),
            let weapon = rechargeableWeapon(on: owner, staves: false)
        else { return nil }
        let share = coordinator.world.perkModified(
            0, at: .modSoulPctCapturedToWeapon, on: killer,
            subjects: PerkEvaluationSubjects(owner: killer, target: victim.key)
                .binding(.item, to: items.conditionSubject(of: weapon.profile.item)),
            seams: ConditionContext()
        )
        guard share > 0 else { return nil }
        let soul = SoulTrap.soul(
            level: runtime.values.baseline(of: victim).level,
            isNPC: coordinator.world.actorHasKeyword("ActorTypeNPC", on: victim),
            settings: coordinator.rules.soulTrap
        )
        return EnchantmentLedger(store: runtime.store, inventory: coordinator.world.inventory)
            .recharge(weapon.profile, by: SoulTrap.charge(of: soul.size) * share, on: owner)
    }
}

extension MagicCoordinator.SoulTrapping {
    /// The first equipped weapon with a metered charge below full.
    func rechargeableWeapon(on holder: ActorValueHolder, staves: Bool)
        -> RechargeableWeapon?
    {
        guard
            let runtime = coordinator.effects,
            let equipment = coordinator.world.equipment else { return nil }
        let ledger = EnchantmentLedger(store: runtime.store, inventory: coordinator.world.inventory)
        return equipment.equipped(on: InventoryHolder(actor: holder)).lazy
            .compactMap {
                coordinator.weaponEnchantments.enchantmentProfile(
                    of: $0,
                    on: InventoryHolder(actor: holder)
                )
            }
            .filter { !$0.isWorn && (staves || !$0.isStaff) }
            .map { RechargeableWeapon(profile: $0, charge: ledger.charge(of: $0, on: holder)) }
            .first { $0.charge.isMetered && $0.charge.remaining < $0.charge.capacity }
    }
}
