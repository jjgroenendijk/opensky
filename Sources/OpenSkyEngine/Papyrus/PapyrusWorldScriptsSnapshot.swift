// Sampling satellite for `PapyrusWorldRuntime` (issue #278): folds the VM's
// instance table, event ring, scheduler counters, and coverage tally into the
// single `ScriptsSnapshot` the World > Scripts sidebar reads.
//
// It lives beside the runtime rather than in the panel so the sampling rules
// — which counters mean what, and how an unimplemented native is ranked — are
// unit-testable without AppKit, exactly like `SWFLabReadout`.

import Foundation

@MainActor
extension PapyrusWorldRuntime {
    /// One sample of the VM for the Scripts readout.
    ///
    /// - Parameters:
    ///   - target: reference the player is currently interacting with, whose
    ///     attached scripts the snapshot names. Nil when nothing is targeted.
    ///   - targetDescription: display text for `target`; defaults to the
    ///     key's own description. Callers that resolved a FormID the streamer
    ///     could not attribute pass their own text instead.
    ///   - runningQuestCount: quests the session's `QuestRuntime` reports as
    ///     running. Passed in rather than read here because quest *state* is
    ///     the world store's, not the VM's; the VM only knows which quests it
    ///     holds instances for.
    ///   - questAliasFillFailures: quests whose alias fill failed at wire-up,
    ///     which the bridge counts rather than the VM (issue #183).
    func scriptsSnapshot(
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
            topUnimplementedNatives: Self.topUnimplementedNatives(tally)
        )
    }

    /// Runs `ticks` fixed steps now, whether or not the VM is paused. The
    /// count is clamped to `maximumBurstTicks` so a stray value from
    /// a control cannot stall the frame.
    func burst(ticks: Int, gameClock: GameClock? = nil) {
        for _ in 0 ..< min(max(0, ticks), Self.maximumBurstTicks) {
            stepFixed(gameClock: gameClock)
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
