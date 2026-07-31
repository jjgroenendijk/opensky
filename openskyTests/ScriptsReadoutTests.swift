// World > Scripts readout coverage (issue #278). Every line the four sections
// show is a pure function of one `ScriptsSnapshot`, so the exact wording is
// asserted here without AppKit, without a Metal device, and without a game
// install. The empty cases matter most: an idle VM and an absent target have to
// read as stated conditions rather than as blanks.

@testable import opensky
import Testing

struct ScriptsReadoutTests {
    @Test
    func instancesTextStatesAnAbsentTarget() {
        let text = ScriptsReadout.instancesText(for: makeScriptsSnapshot(instanceCount: 9))
        #expect(text == "Instances: 9\nTarget: none")
    }

    /// A targeted reference carrying no scripts is a different fact from no
    /// target at all, and the readout has to tell them apart.
    @Test
    func instancesTextSeparatesNoTargetFromNoScripts() {
        let text = ScriptsReadout.instancesText(
            for: makeScriptsSnapshot(instanceCount: 3, targetDescription: "skyrim.esm:00003F")
        )
        #expect(text.contains("Target: skyrim.esm:00003F"))
        #expect(text.contains("Target scripts: none"))
    }

    @Test
    func instancesTextListsAttachedScripts() {
        let text = ScriptsReadout.instancesText(
            for: makeScriptsSnapshot(
                instanceCount: 3,
                targetDescription: "skyrim.esm:00003F",
                targetScripts: ["defaultAlias", "WIChangeLocation04"]
            )
        )
        #expect(text.contains("Target scripts: defaultAlias, WIChangeLocation04"))
    }

    @Test
    func eventsTextStatesAnEmptyRing() {
        let text = ScriptsReadout.eventsText(for: .empty)
        #expect(text == "Pending events: 0  Dropped: 0\nNo events dispatched yet.")
    }

    /// The tail is most recent last, the same presentation the Runtime State
    /// journal uses, and the dropped count is shown rather than hidden.
    @Test
    func eventsTextShowsTheTailOldestFirst() {
        let text = ScriptsReadout.eventsText(
            for: makeScriptsSnapshot(
                recentEvents: ["OnActivate a", "OnTriggerEnter b"],
                droppedRecentEventCount: 4,
                pendingEventCount: 2
            )
        )
        #expect(text == """
        Pending events: 2  Dropped: 4
        OnActivate a
        OnTriggerEnter b
        """)
    }

    @Test
    func schedulerTextReportsRunningAndPausedStates() {
        #expect(ScriptsReadout.schedulerText(for: .empty).hasPrefix("VM: running"))
        #expect(
            ScriptsReadout.schedulerText(for: makeScriptsSnapshot(isPaused: true))
                .hasPrefix("VM: paused")
        )
    }

    @Test
    func schedulerTextCarriesEveryCounterTheGateNames() {
        let text = ScriptsReadout.schedulerText(
            for: makeScriptsSnapshot(
                pendingWaitCount: 2,
                pendingTimerCount: 5,
                tickCount: 120,
                budgetEvents: 100,
                budgetInstructions: 20000,
                lastTickSteps: 4,
                lastTickDispatched: 3,
                lastTickQueued: 1,
                lastTickResumed: 2,
                lastTickFaulted: 1
            )
        )
        #expect(text.contains("Pending waits: 2  Pending timers: 5"))
        #expect(text.contains("Ticks: 120  Budget: 100 events / 20000 instructions"))
        #expect(
            text.contains(
                "Last tick: steps 4 · dispatched 3 · queued 1 · resumed 2 · faulted 1"
            )
        )
    }

    @Test
    func nativeTallyTextStatesFullCoverage() {
        let text = ScriptsReadout.nativeTallyText(
            for: makeScriptsSnapshot(nativeCallTotal: 40, implementedNativeNameCount: 6)
        )
        #expect(text == """
        Native calls: 40
        Implemented names: 6  Unimplemented calls: 0
        Top unimplemented: none
        """)
    }

    /// The ranked list is numbered so the worst offender is unambiguous, and it
    /// preserves the order the snapshot ranked.
    @Test
    func nativeTallyTextRanksUnimplementedNatives() {
        let text = ScriptsReadout.nativeTallyText(
            for: makeScriptsSnapshot(
                nativeCallTotal: 4210,
                implementedNativeNameCount: 37,
                unimplementedNativeTotal: 12,
                topUnimplementedNatives: [
                    ScriptsNativeCount(name: "Game.GetPlayer", count: 8),
                    ScriptsNativeCount(name: "ObjectReference.PlayAnimation", count: 4)
                ]
            )
        )
        #expect(text.contains("Implemented names: 37  Unimplemented calls: 12"))
        #expect(text.contains("1. Game.GetPlayer 8"))
        #expect(text.contains("2. ObjectReference.PlayAnimation 4"))
    }
}
