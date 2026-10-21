// The per-second check of a stored effect's entry conditions. "In most cases, an
// effect's spell-side conditions are checked every second while an actor has the
// effect" (<https://ck.uesp.net/wiki/Magic_Effect>). A failing check suspends the
// effect: it gives its slot back and pays nothing until the check passes again.
// See docs/engine/magic.md#conditions.

import Foundation
import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

extension ActiveEffectRuntime {
    /// How often the entry conditions of a stored effect are checked.
    public static let conditionCheckSeconds: Float = 1

    /// Counts `seconds` toward the next check and runs it once a second passes.
    mutating func advanceConditionClock(by seconds: Float, over holders: [ActorValueHolder]) {
        conditionClock += seconds
        guard conditionClock + ActiveEffect.secondTolerance >= Self.conditionCheckSeconds
        else { return }
        conditionClock = max(0, conditionClock - Self.conditionCheckSeconds)
        for holder in holders {
            recheckConditions(on: holder)
        }
    }

    /// Suspends every effect on `holder` whose entry conditions now fail, and
    /// resumes every suspended one whose conditions now pass.
    /// - Returns: how many effects changed.
    @discardableResult
    public mutating func recheckConditions(on holder: ActorValueHolder) -> Int {
        let state = state(of: holder)
        let applying = application
        defer { application = applying }
        var changed: [ActiveEffect] = []
        for effect in state.effects {
            guard let list = entryConditions(effect), !list.conditions.isEmpty else { continue }
            application.isDualCast = effect.wasDualCast
            let holds = allows(list, on: holder)
            guard holds == effect.isSuspended else { continue }
            changed.append(holds ? resume(effect, on: holder) : suspend(effect, on: holder))
            tally.noteSuspension(!holds)
        }
        guard !changed.isEmpty else { return 0 }
        write(self.state(of: holder).replacing(changed), for: holder)
        return changed.count
    }

    private mutating func suspend(_ effect: ActiveEffect, on holder: ActorValueHolder)
        -> ActiveEffect
    {
        release([effect], on: holder)
        return effect.suspended(true)
    }

    private mutating func resume(_ effect: ActiveEffect, on holder: ActorValueHolder)
        -> ActiveEffect
    {
        var resumed = effect.suspended(false)
        if effect.mode.ownsModifierSlot, rule(of: effect) != .accumulate {
            resumed = resumed.owningModifiers(claim(resumed, on: holder))
        }
        if let action = worldAction(.began, of: resumed, on: holder) {
            worldActions.append(action)
        }
        return resumed
    }
}
