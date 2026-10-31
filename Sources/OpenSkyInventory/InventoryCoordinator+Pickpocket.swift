// Pickpocketing: a take from a living actor, or a place into its pocket, rolls the
// chance. A take moves the item stolen and teaches Pickpocket by its value; a failure
// moves nothing and reports the crime. See docs/engine/pickpocket.md.

import OpenSkyConditions
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface

nonisolated public enum PickpocketText: String, GameSettingTextKey {
    /// The HUD notice when the target notices.
    case caught = "sPickpocketFail"
    /// Follows the target's name, so it starts with a space.
    case caughtBefore = "sNoPickPocketAgain"

    public var fallback: String {
        switch self {
        case .caught: "You've been caught pickpocketing."
        case .caughtBefore: " has already caught you."
        }
    }
}

/// A target that caught the player refuses another try for two game days
/// (UESP "Skyrim:Pickpocket").
nonisolated public enum PickpocketCooldown {
    public static let days: Float = 2

    public static func refuses(caughtOn day: Float?, today: Float?) -> Bool {
        guard let day, let today else { return false }
        return today - day < days
    }
}

/// What one pickpocket take did.
nonisolated public enum PickpocketOutcome: Equatable, Sendable {
    case took(item: String, chance: Int)
    case placed(item: String, chance: Int)
    /// The Poisoned perk: a placed poison lands on the target instead.
    case poisoned(item: String, chance: Int)
    /// The roll failed: the target noticed and the crime was reported.
    case caught(item: String, chance: Int, bounty: Int32)
    /// An equipped item needs a Can Pickpocket Equipped Item perk.
    case equipped(String)
    case failed(String)
    case unavailable

    public var text: String {
        switch self {
        case let .took(item, chance): "Pickpocketed \(item) (\(chance)% chance)."
        case let .placed(item, chance): "Placed \(item) (\(chance)% chance)."
        case let .poisoned(item, chance): "Poisoned the target with \(item) (\(chance)% chance)."
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
    /// Whether `target` refuses a pickpocket now, because it caught the player lately.
    public func pickpocketRefused(by target: ReferenceKey) -> Bool {
        PickpocketCooldown.refuses(
            caughtOn: world.pickpocketCaughtDay(of: target), today: world.gameDaysPassed
        )
    }

    private func caught(
        by target: InventoryHolder, item: String, chance: Float, runtime: WorldItemRuntime
    ) -> PickpocketOutcome {
        let crime = runtime.crime?.reportPickpocket(of: target.key, by: .player)
        world.notePickpocketCatch(
            on: world.gameDaysPassed, chargedTo: crime?.faction, by: target.key
        )
        return .caught(item: item, chance: Int(chance), bounty: crime?.gold ?? 0)
    }

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
            subjects: pickpocketSubjects(item, target: target),
            seams: ConditionContext()
        )
        return pickpocketSettings.clamped(chance)
    }

    /// The target, and the item for the perks' item tab, such as Cutpurse's gold test
    /// or Poisoned's `IsPoison`.
    private func pickpocketSubjects(_ item: FormID, target: InventoryHolder)
        -> PerkEvaluationSubjects
    {
        PerkEvaluationSubjects(owner: .player, target: target.key)
            .binding(.item, to: runtime?.inventory.baselines.items.conditionSubject(of: item))
    }

    /// Whether a perk entry point that answers yes or no says yes for `item`.
    private func pickpocketPerkAllows(
        _ entryPoint: PerkEntryPoint, item: FormID, target: InventoryHolder
    ) -> Bool {
        world.perkModified(
            0, at: entryPoint, on: .player,
            subjects: pickpocketSubjects(item, target: target), seams: ConditionContext()
        ) > 0
    }

    /// One place into `target`'s pocket. It rolls the take chance, so a heavy item is
    /// hard to place. With Should Apply Placed Item (the Poisoned perk) a poison lands
    /// on the target instead of going into the pocket.
    @discardableResult
    public func plant(
        _ item: FormID, count: Int32 = 1, named name: String, into target: InventoryHolder,
        roll: Float
    ) -> PickpocketOutcome {
        guard let runtime else { return .unavailable }
        let chance = pickpocketChance(of: item, count: count, from: target)
        guard roll < chance else {
            return caught(by: target, item: name, chance: chance, runtime: runtime)
        }
        do {
            if
                isPoison(item), pickpocketPerkAllows(
                    .shouldApplyPlacedItem,
                    item: item,
                    target: target
                )
            {
                guard runtime.inventory.count(of: item, in: runtime.player) > 0 else {
                    return .failed("\(name) is not carried")
                }
                guard world.applyPlacedPoison(item, on: target.key) else {
                    return .failed("the poison did not land on \(target.key)")
                }
                try runtime.inventory.remove(item, count: 1, from: runtime.player)
                return .poisoned(item: name, chance: Int(chance))
            }
            try runtime.inventory.transfer(item, count: count, from: runtime.player, to: target)
        } catch {
            return .failed(String(describing: error))
        }
        return .placed(item: name, chance: Int(chance))
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
            !pickpocketPerkAllows(.canPickpocketEquippedItem, item: item, target: target)
        {
            return .equipped(name)
        }
        let chance = pickpocketChance(of: item, count: count, from: target)
        guard roll < chance else {
            return caught(by: target, item: name, chance: chance, runtime: runtime)
        }
        do {
            try runtime.inventory.transfer(
                item, count: count, from: target, to: runtime.player, markingStolen: true
            )
        } catch {
            return .failed(String(describing: error))
        }
        let value = runtime.inventory.baselines.items.gameValue(of: item)
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
