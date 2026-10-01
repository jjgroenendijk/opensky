// Snapshot builder for the World > Scripts seam, shared by the readout suite and
// the panel suite.

@testable import OpenSkyScripting

/// Builds a `ScriptsSnapshot` from only the fields a test cares about. The
/// snapshot is immutable by design and its memberwise initializer takes twenty
/// arguments, so a test that wants one non-zero counter would otherwise have to
/// spell out the other nineteen.
nonisolated public func makeScriptsSnapshot(
    instanceCount: Int = 0,
    targetDescription: String? = nil,
    targetScripts: [String] = [],
    recentEvents: [String] = [],
    droppedRecentEventCount: Int = 0,
    pendingEventCount: Int = 0,
    isPaused: Bool = false,
    questInstanceCount: Int = 0,
    questCount: Int = 0,
    runningQuestCount: Int = 0,
    questFragmentsQueued: Int = 0,
    lastQuestFragment: String? = nil,
    questAliasInstanceCount: Int = 0,
    filledAliasCount: Int = 0,
    aliasQuestCount: Int = 0,
    questAliasFillFailures: Int = 0,
    lastQuestAliasFill: String? = nil,
    pendingWaitCount: Int = 0,
    pendingTimerCount: Int = 0,
    tickCount: Int = 0,
    budgetEvents: Int = 0,
    budgetInstructions: Int = 0,
    lastTickSteps: Int = 0,
    lastTickDispatched: Int = 0,
    lastTickQueued: Int = 0,
    lastTickResumed: Int = 0,
    lastTickFaulted: Int = 0,
    nativeCallTotal: Int = 0,
    implementedNativeNameCount: Int = 0,
    unimplementedNativeTotal: Int = 0,
    topUnimplementedNatives: [ScriptsNativeCount] = []
) -> ScriptsSnapshot {
    ScriptsSnapshot(
        instanceCount: instanceCount,
        targetDescription: targetDescription,
        targetScripts: targetScripts,
        questInstanceCount: questInstanceCount,
        questCount: questCount,
        runningQuestCount: runningQuestCount,
        questFragmentsQueued: questFragmentsQueued,
        lastQuestFragment: lastQuestFragment,
        questAliasInstanceCount: questAliasInstanceCount,
        filledAliasCount: filledAliasCount,
        aliasQuestCount: aliasQuestCount,
        questAliasFillFailures: questAliasFillFailures,
        lastQuestAliasFill: lastQuestAliasFill,
        recentEvents: recentEvents,
        droppedRecentEventCount: droppedRecentEventCount,
        pendingEventCount: pendingEventCount,
        isPaused: isPaused,
        pendingWaitCount: pendingWaitCount,
        pendingTimerCount: pendingTimerCount,
        tickCount: tickCount,
        budgetEvents: budgetEvents,
        budgetInstructions: budgetInstructions,
        lastTickSteps: lastTickSteps,
        lastTickDispatched: lastTickDispatched,
        lastTickQueued: lastTickQueued,
        lastTickResumed: lastTickResumed,
        lastTickFaulted: lastTickFaulted,
        nativeCallTotal: nativeCallTotal,
        implementedNativeNameCount: implementedNativeNameCount,
        unimplementedNativeTotal: unimplementedNativeTotal,
        topUnimplementedNatives: topUnimplementedNatives
    )
}
