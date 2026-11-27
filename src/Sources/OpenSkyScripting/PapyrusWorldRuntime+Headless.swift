// What a headless run over real content needs from the runtime: the fallbacks it met, by
// name, a bounded drain of the event queue, and a quest stage's fragments queued on their
// own (docs/tools/headless-sweeps.md).

import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Every place the run met something it does not handle: the VM's own, then each event
    /// or property binding it skipped.
    public var fallbacks: [(name: String, count: Int)] {
        runtime.tally.fallbacks
            + skips.ranked.map { ("script skip \($0.name)", $0.count) }
            + bindingSkips.ranked.map { ("property binding skip \($0.name)", $0.count) }
    }

    /// Steps until a step neither dispatches, resumes, nor leaves anything queued or waiting.
    /// - Returns: false when the queue was still busy after `maxSteps`.
    @discardableResult
    public func drain(maxSteps: Int = 64) -> Bool {
        for _ in 0 ..< maxSteps {
            let report = scriptEvents.stepFixed()
            if
                report.dispatched == 0, report.resumed == 0, report.queued == 0,
                scheduler.pendingCalls.isEmpty
            {
                return true
            }
        }
        return false
    }

    /// Drops every call still waiting, so a headless run's next subject starts clean.
    public func dropWaitingCalls() {
        scheduler.cancelAll()
    }

    /// Queues the fragments `quest` attaches to `stage`, whether or not the stage is set.
    /// - Returns: events queued.
    @discardableResult
    public func queueStageFragments(of quest: Quest, stage: UInt16, key: ReferenceKey) -> Int {
        questRuns.queueQuestFragments(of: quest, stage: stage, key: key)
    }
}
