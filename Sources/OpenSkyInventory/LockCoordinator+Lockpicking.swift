// Running and ending a lockpicking session: a broken pick leaves the inventory, skill
// use is reported, and an opened lock unlocks. See docs/engine/locks.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyInventoryInterface
import OpenSkyProgressionInterface
import OpenSkyWorldInterface

extension LockCoordinator {
    /// Advances the open session. Returns its events; empty without a session.
    @discardableResult
    public func stepLockpicking(_ seconds: Float, input: LockpickingInput) -> [LockpickingEvent] {
        guard var current = session else { return [] }
        let events = current.step(seconds, input: input)
        session = current
        pickHealth = current.pickHealth
        for event in events {
            handle(event)
        }
        return events
    }

    /// Ends the open session without opening the lock.
    @discardableResult
    public func cancelLockpicking() -> [LockpickingEvent] {
        guard var current = session else { return [] }
        let events = current.cancel()
        session = current
        for event in events {
            handle(event)
        }
        return events
    }

    /// Drops a finished session, after the menu has shown its last frame.
    public func closeLockpicking() {
        guard session?.isFinished != false else { return }
        session = nil
        sessionTarget = nil
        sessionLock = nil
    }

    private func handle(_ event: LockpickingEvent) {
        switch event {
        case .pickBroke:
            if let items, let lockpickItem {
                _ = try? items.inventory.remove(lockpickItem, count: 1, from: items.player)
            }
            sessionExperience += report(uses: settings.brokenUses)
            lastText = "A lockpick broke."
        case .opened:
            open()
        case .outOfPicks:
            finish(opened: false, keyRewarded: false)
            lastText = "Out of lockpicks."
        case .cancelled:
            finish(opened: false, keyRewarded: false)
            lastText = "Stopped picking."
        }
    }

    private func open() {
        guard let target = sessionLock else { return }
        write(target.state, locked: false, for: target.key)
        sessionExperience += report(uses: settings.successUses[target.state.difficulty] ?? 0)
        let rewarded = rewardKey(target)
        finish(opened: true, keyRewarded: rewarded)
        lastText = "Picked \(sessionTarget?.interaction.name ?? "the lock")."
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

    private func report(uses: Float) -> Float {
        guard uses > 0, let world, let items else { return 0 }
        return world.reportSkillUse(SkillUseEvent(
            actor: items.player.key, action: .lockpick, amount: uses
        ))
    }

    private func finish(opened: Bool, keyRewarded: Bool) {
        guard let target = sessionLock else { return }
        lastOutcome = LockpickingOutcome(
            difficulty: target.state.difficulty,
            opened: opened,
            picksBroken: session?.picksBroken ?? 0,
            experience: sessionExperience,
            keyRewarded: keyRewarded
        )
    }
}
