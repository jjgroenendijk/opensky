// Pickpocketing: a take from a living actor rolls the chance. A success moves the item
// stolen and teaches Pickpocket by its value; a failure moves nothing and reports the
// crime. See docs/engine/pickpocket.md.

import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface

/// What one pickpocket take did.
nonisolated public enum PickpocketOutcome: Equatable, Sendable {
    case took(item: String, chance: Int)
    /// The roll failed: the target noticed and the crime was reported.
    case caught(item: String, chance: Int, bounty: Int32)
    /// An equipped item needs a Can Pickpocket Equipped Item perk.
    case equipped(String)
    case failed(String)
    case unavailable

    public var text: String {
        switch self {
        case let .took(item, chance): "Pickpocketed \(item) (\(chance)% chance)."
        case let .caught(item, chance, bounty):
            "Caught taking \(item) (\(chance)% chance); bounty \(bounty)."
        case let .equipped(item): "\(item) is equipped and cannot be taken."
        case let .failed(reason): "Pickpocket refused: \(reason)"
        case .unavailable: InventoryCore.noRuntimeText
        }
    }

    public var wasCaught: Bool {
        if case .caught = self {
            return true
        }
        return false
    }
}

extension InventoryCoordinator {
    /// The chance in percent of taking `count` of `item` from `target` now.
    public func pickpocketChance(of item: FormID, count: Int32, from target: InventoryHolder)
        -> Float
    {
        guard let runtime else { return 0 }
        let definition = runtime.inventory.baselines.items.definition(item)
        let isGold = item == runtime.inventory.goldFormID
        let attempt = PickpocketAttempt(
            thiefSkill: world.pickpocketSkill(of: .player) ?? ActorValueIdentity.skillFloor,
            targetSkill: world.pickpocketSkill(of: target.key) ?? ActorValueIdentity.skillFloor,
            gold: isGold ? count : 0,
            weight: (definition?.weight ?? 0) * Float(count),
            detected: world.detectsPlayer(target.key)
        )
        let chance = world.perkModified(
            pickpocketSettings.baseChance(attempt),
            at: .modPickpocketChance,
            on: .player,
            subjects: PerkEvaluationSubjects(owner: .player, target: target.key),
            seams: ConditionContext()
        )
        return pickpocketSettings.clamped(chance)
    }

    /// One take from `target`'s pocket. `roll` is in 0 to 100; a roll below the
    /// chance succeeds.
    @discardableResult
    public func pickpocket(
        _ item: FormID, count: Int32 = 1, named name: String, from target: InventoryHolder,
        roll: Float
    ) -> PickpocketOutcome {
        guard let runtime else { return .unavailable }
        if
            runtime.inventory.inventory(of: target).equipped.contains(item),
            world.perkModified(
                0, at: .canPickpocketEquippedItem, on: .player,
                subjects: PerkEvaluationSubjects(owner: .player, target: target.key),
                seams: ConditionContext()
            ) <= 0
        {
            return .equipped(name)
        }
        let chance = pickpocketChance(of: item, count: count, from: target)
        guard roll < chance else {
            let bounty = runtime.crime?.reportPickpocket(of: target.key, by: .player).gold ?? 0
            return .caught(item: name, chance: Int(chance), bounty: bounty)
        }
        do {
            try runtime.inventory.transfer(
                item, count: count, from: target, to: runtime.player, markingStolen: true
            )
        } catch {
            return .failed(String(describing: error))
        }
        let value = runtime.inventory.baselines.items.definition(item)?.value ?? 0
        let isGold = item == runtime.inventory.goldFormID
        skillUses?.reportSkillUse(SkillUseEvent(
            actor: .player, action: .pickpocket, amount: Float(isGold ? count : value * count)
        ))
        storyEvents?.reportStoryEvent(.addItem(
            item, from: target.key, owner: nil, how: .pickpocket
        ))
        return .took(item: name, chance: Int(chance))
    }
}
