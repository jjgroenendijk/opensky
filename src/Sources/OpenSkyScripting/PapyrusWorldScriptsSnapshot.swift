// Folds the VM's instance table, event ring, scheduler counters and tally into the
// `ScriptsSnapshot` agent control reads. Here, so the sampling rules are
// testable without AppKit.

import Foundation
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState

@MainActor
extension PapyrusWorldRuntime.Readouts {
    /// One VM sample for the Scripts readout. `target` is the interacted reference, or
    /// nil. `runningQuestCount` comes from `QuestRuntime`, because quest state is the
    /// store's. `questAliasFillFailures` comes from the bridge.
    func scriptsSnapshot(
        target: ReferenceKey? = nil,
        targetDescription: String? = nil,
        runningQuestCount: Int = 0,
        questAliasFillFailures: Int = 0
    ) -> ScriptsSnapshot {
        let tally = world.runtime.tally
        return ScriptsSnapshot(
            instanceCount: world.instancesByKey.count,
            targetDescription: targetDescription ?? target?.description,
            targetScripts: scriptNames(attachedTo: target),
            questInstanceCount: world.questInstanceKeys.count,
            questCount: world.questRuns.questCount,
            runningQuestCount: runningQuestCount,
            questFragmentsQueued: world.questFragmentsQueued,
            lastQuestFragment: world.lastQuestFragment,
            questAliasInstanceCount: world.questRuns.questAliasInstanceCount,
            filledAliasCount: world.aliasResolution.filledAliasCount,
            aliasQuestCount: world.aliasResolution.filledQuestCount,
            questAliasFillFailures: questAliasFillFailures,
            lastQuestAliasFill: world.lastQuestAliasFill,
            recentEvents: world.recentEvents,
            droppedRecentEventCount: world.droppedRecentEventCount,
            pendingEventCount: world.eventQueue.count,
            isPaused: world.isPaused,
            pendingWaitCount: world.scheduler.pendingCount,
            pendingTimerCount: world.updateTimers.pendingCount,
            tickCount: world.scheduler.tickCount,
            budgetEvents: world.budget.events,
            budgetInstructions: world.budget.instructions,
            lastTickSteps: world.lastTickReport.steps,
            lastTickDispatched: world.lastTickReport.dispatched,
            lastTickQueued: world.lastTickReport.queued,
            lastTickResumed: world.lastTickReport.resumed,
            lastTickFaulted: world.lastTickReport.faulted,
            nativeCallTotal: tally.nativeCallTotal,
            implementedNativeNameCount: Self.implementedNativeNameCount(tally),
            unimplementedNativeTotal: tally.unimplementedNativeTotal,
            topUnimplementedNatives: Self.topUnimplementedNatives(tally),
            lastFault: tally.lastFault,
            lastStepInstructions: world.lastStepInstructions,
            usesGameTiming: world.runtime.nativeTiming == .game,
            lastStepDelayedCalls: world.lastStepDelayedCalls
        )
    }

    /// Runs `ticks` fixed steps now, whether or not the VM is paused. The
    /// count is clamped to `maximumBurstTicks` so a stray value from
    /// a control cannot stall the frame.
    func burst(ticks: Int, gameClock: GameClock? = nil) {
        for _ in 0 ..< min(max(0, ticks), Self.maximumBurstTicks) {
            world.scriptEvents.stepFixed(gameClock: gameClock)
        }
    }

    /// Upper bound on one `burst(ticks:gameClock:)` call. Sixty steps is two
    /// seconds at the 1/30 s fixed step: long enough to walk a latent
    /// `Utility.Wait` through, short enough to stay imperceptible.
    static let maximumBurstTicks = 60

    /// Sorted script names attached to `key`, empty when it is nil or carries
    /// no instances.
    private func scriptNames(attachedTo key: ReferenceKey?) -> [String] {
        guard let key else { return [] }
        return world.instanceKeys(on: key).map(\.scriptName)
    }

    /// Distinct native names the session called that never reported
    /// `PapyrusNativeFailure.unimplemented`. Observed coverage, not
    /// registered coverage: a native nothing called yet is not counted.
    private static func implementedNativeNameCount(_ tally: PapyrusTally) -> Int {
        tally.nativeCallCounts.keys.count {
            tally.unimplementedNativeCounts[$0] == nil
        }
    }

    private static func topUnimplementedNatives(
        _ tally: PapyrusTally
    ) -> [ScriptsNativeCount] {
        tally.rankedUnimplementedNatives
            .prefix(ScriptsSnapshot.topUnimplementedNativeLimit)
            .map { ScriptsNativeCount(name: $0.name, count: $0.count) }
    }
}
