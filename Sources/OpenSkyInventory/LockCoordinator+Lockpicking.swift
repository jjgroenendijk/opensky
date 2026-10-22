// Running and ending a lockpicking session: a broken pick leaves the inventory, skill
// use is reported, and an opened lock unlocks. See docs/engine/locks.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldInterface

extension LockCoordinator {
    /// Advances the open session. Returns its events; empty without a session.
    public func stepLockpicking(
        _ seconds: Float, input: LockpickingInput
    ) -> InventoryResult<[LockpickingEvent]> {
        guard var current = session else { return InventoryResult([]) }
        let events = current.step(seconds, input: input)
        session = current
        pickHealth = current.pickHealth
        return InventoryResult(events, commands: events.flatMap(handle))
    }

    /// Ends the open session without opening the lock.
    public func cancelLockpicking() -> InventoryResult<[LockpickingEvent]> {
        guard var current = session else { return InventoryResult([]) }
        let events = current.cancel()
        session = current
        return InventoryResult(events, commands: events.flatMap(handle))
    }

    /// Drops a finished session, after the menu has shown its last frame.
    public func closeLockpicking() {
        guard session?.isFinished != false else { return }
        session = nil
        sessionTarget = nil
        sessionLock = nil
    }

    private func handle(_ event: LockpickingEvent) -> [InventoryCommand] {
        switch event {
        case .pickBroke:
            if let items, let lockpickItem {
                _ = try? items.inventory.remove(lockpickItem, count: 1, from: items.player)
            }
            sessionExperience += report(uses: settings.brokenUses, action: .lockpickBroken)
            lastAction = .pickBroke
            if let bounty = reportCrime(), bounty > 0 {
                // UESP: a pick broken while seen closes the window and resets the lock.
                if var current = session {
                    _ = current.cancel()
                    session = current
                }
                finish(opened: false, keyRewarded: false)
                lastAction = .caughtPicking(bounty: bounty)
            }
            return []
        case .opened:
            let commands = open()
            if let bounty = reportCrime(), bounty > 0 {
                lastAction = .caughtPicking(bounty: bounty)
            }
            return commands
        case .outOfPicks:
            finish(opened: false, keyRewarded: false)
            lastAction = .notice(.outOfLockpicks)
            return [.showNotice(texts.outOfLockpicks)]
        case .cancelled:
            finish(opened: false, keyRewarded: false)
            lastAction = .stoppedPicking
            return []
        }
    }

    private func open() -> [InventoryCommand] {
        guard let target = sessionLock else { return [] }
        let commands = write(target.state, locked: false, for: target.key)
        sessionExperience += report(
            uses: settings.successUses[target.difficulty] ?? 0, action: .lockpickSuccess
        )
        let rewarded = rewardKey(target)
        if let items {
            storyEvents?.reportStoryEvent(.lockPick(actor: items.player.key, lock: target.key))
        }
        world.countLockPicked()
        finish(opened: true, keyRewarded: rewarded)
        lastAction = .picked(name: sessionTarget?.interaction.name)
        return commands
    }

    /// A seen pick of an owned lock is a crime, unless the crime chance roll says the
    /// player was not noticed. UESP "Skyrim:Lockpicking": opening the window is no
    /// crime, a success or a broken pick is.
    private func reportCrime() -> Int32? {
        guard let target = sessionLock, target.perks.crimeChance > 0 else { return nil }
        guard
            target.perks.crimeChance >= 1 || random.uniform(in: 0 ... 1) < target.perks
                .crimeChance
        else { return nil }
        return world.reportLockpickingCrime(on: target.key)
    }

    /// `Mod Lockpicking Key Reward Chance` in percent. Wax Key sets 100.
    private func rewardKey(_ target: LockpickingTarget) -> Bool {
        guard
            let key = target.state.key,
            let items,
            target.perks.keyRewardChance > 0,
            items.inventory.count(of: key, in: items.player) == 0,
            random.uniform(in: 0 ... 100) < target.perks.keyRewardChance
        else { return false }
        return (try? items.inventory.add(key, count: 1, to: items.player)) != nil
    }

    private func report(uses: Float, action: SkillAdvanceAction) -> Float {
        guard uses > 0, let items else { return 0 }
        return world.reportSkillUse(SkillUseEvent(
            actor: items.player.key, action: .lockpick, amount: uses, advanceAction: action
        ))
    }

    private func finish(opened: Bool, keyRewarded: Bool) {
        guard let target = sessionLock else { return }
        lastOutcome = LockpickingOutcome(
            difficulty: target.difficulty,
            opened: opened,
            picksBroken: session?.picksBroken ?? 0,
            experience: sessionExperience,
            keyRewarded: keyRewarded
        )
    }
}
