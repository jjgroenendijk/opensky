// The session side of soul trap: a death under the effect, or `Actor.TrapSoul`, fills
// the smallest empty gem the player carries. Only the player's gems are filled; an NPC
// caster's trap catches nothing. See docs/engine/soul-trap.md.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

/// What one soul trap did.
nonisolated public enum SoulTrapOutcome: Equatable, Sendable {
    case trapped(TrappedSoul, gem: FormID)
    /// No empty gem the player carries holds the soul.
    case noGem(TrappedSoul)
    /// The trap was not the player's, or the session cannot fill a gem.
    case notFilled
}

extension MagicCoordinator {
    /// Called once for each death. Soul Siphon feeds the killer's weapon, then the soul
    /// is trapped when a soul trap effect is on the dying actor.
    @discardableResult
    public func noteDeath(
        of victim: ReferenceKey,
        killer: ReferenceKey? = nil
    ) -> SoulTrapOutcome? {
        guard
            let effects,
            let holder = world.actorValueHolder(for: victim)
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
            let inventory = world.inventory,
            let effects,
            let holder = world.actorValueHolder(for: victim)
        else { return .notFilled }
        let soul = SoulTrap.soul(
            level: effects.values.baseline(of: holder).level,
            isNPC: world.actorHasKeyword("ActorTypeNPC", on: holder),
            settings: soulTrapSettings
        )
        guard let chosen = SoulTrap.gem(for: soul, among: carriedGems(inventory)) else {
            world.postNotification(magicTexts.word(
                "sSoulGemTooSmall",
                or: "No soul gem large enough"
            ))
            return .noGem(soul)
        }
        fill(chosen, with: soul, in: inventory)
        world.postNotification(magicTexts.word("sSoulCaptured", or: "Soul captured!"))
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
            (try? inventory.remove(gem.item, count: 1, from: .player)) != nil
        {
            _ = try? inventory.add(linked, count: 1, to: .player)
            return
        }
        let size = soul.size.rawValue
        inventory.editCopy(of: gem.item, in: .player, where: { $0 == gem.copy }, { $0.soul = size })
    }
}
