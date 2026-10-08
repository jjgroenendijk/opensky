// Folds the VM's instance table, event ring, scheduler counters and tally into the
// `ScriptsSnapshot` the World > Scripts sidebar reads. Here, so the sampling rules are
// testable without AppKit.

import Foundation
import OpenSkyFormatsESM
import OpenSkyQuestsInterface
import OpenSkyScriptingInterface
import OpenSkyWorldState

@MainActor
extension PapyrusWorldRuntime {
    /// One VM sample for the Scripts readout. `target` is the interacted reference, or
    /// nil. `runningQuestCount` comes from `QuestRuntime`, because quest state is the
    /// store's. `questAliasFillFailures` comes from the bridge.
    public func scriptsSnapshot(
        target: ReferenceKey? = nil,
        targetDescription: String? = nil,
        runningQuestCount: Int = 0,
        questAliasFillFailures: Int = 0
    ) -> ScriptsSnapshot {
        let tally = runtime.tally
        return ScriptsSnapshot(
            instanceCount: instancesByKey.count,
            targetDescription: targetDescription ?? target?.description,
            targetScripts: scriptNames(attachedTo: target),
            questInstanceCount: questInstanceKeys.count,
            questCount: questCount,
            runningQuestCount: runningQuestCount,
            questFragmentsQueued: questFragmentsQueued,
            lastQuestFragment: lastQuestFragment,
            questAliasInstanceCount: questAliasInstanceCount,
            filledAliasCount: aliasResolution.filledAliasCount,
            aliasQuestCount: aliasResolution.filledQuestCount,
            questAliasFillFailures: questAliasFillFailures,
            lastQuestAliasFill: lastQuestAliasFill,
            recentEvents: recentEvents,
            droppedRecentEventCount: droppedRecentEventCount,
            pendingEventCount: eventQueue.count,
            isPaused: isPaused,
            pendingWaitCount: scheduler.pendingCount,
            pendingTimerCount: updateTimers.pendingCount,
            tickCount: scheduler.tickCount,
            budgetEvents: budget.events,
            budgetInstructions: budget.instructions,
            lastTickSteps: lastTickReport.steps,
            lastTickDispatched: lastTickReport.dispatched,
            lastTickQueued: lastTickReport.queued,
            lastTickResumed: lastTickReport.resumed,
            lastTickFaulted: lastTickReport.faulted,
            nativeCallTotal: tally.nativeCallTotal,
            implementedNativeNameCount: Self.implementedNativeNameCount(tally),
            unimplementedNativeTotal: tally.unimplementedNativeTotal,
            topUnimplementedNatives: Self.topUnimplementedNatives(tally),
            lastFault: tally.lastFault
        )
    }

    /// Runs `ticks` fixed steps now, whether or not the VM is paused. The
    /// count is clamped to `maximumBurstTicks` so a stray value from
    /// a control cannot stall the frame.
    public func burst(ticks: Int, gameClock: GameClock? = nil) {
        for _ in 0 ..< min(max(0, ticks), Self.maximumBurstTicks) {
            stepFixed(gameClock: gameClock)
        }
    }

    /// Upper bound on one `burst(ticks:gameClock:)` call. Sixty steps is two
    /// seconds at the 1/30 s fixed step: long enough to walk a latent
    /// `Utility.Wait` through, short enough to stay imperceptible.
    public static let maximumBurstTicks = 60

    /// Sorted script names attached to `key`, empty when it is nil or carries
    /// no instances.
    private func scriptNames(attachedTo key: ReferenceKey?) -> [String] {
        guard let key else { return [] }
        return instancesByKey.keys
            .filter { $0.reference == key }
            .map(\.scriptName)
            .sorted()
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
