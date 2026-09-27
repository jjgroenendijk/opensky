// M11 milestone panel acceptance (issue #174): one uninterrupted run through
// the real sidebar model and registry-built World > Scripts panel on a single
// provider set. The readouts are found by their accessibility identifiers,
// which is the deterministic substitute while UI automation is TCC-blocked.

import AppKit
@testable import opensky
import Testing

@MainActor
struct M11AcceptancePanelTests {
    @Test
    func scriptsDestinationRunsTheWholeAcceptanceFlow() throws {
        let providers = FakeWorldProviders()
        providers.scripts.scriptsSnapshot = makeScriptsSnapshot(
            instanceCount: 2,
            targetDescription: "skyrim.esm:000022",
            targetScripts: ["LeverScript"],
            recentEvents: ["OnActivate -> leverscript"],
            pendingEventCount: 1,
            pendingTimerCount: 1,
            tickCount: 12,
            budgetEvents: 100,
            budgetInstructions: 20000,
            lastTickSteps: 1,
            lastTickDispatched: 1,
            nativeCallTotal: 3,
            implementedNativeNameCount: 2,
            unimplementedNativeTotal: 0
        )

        let worldGroup = try #require(
            AppSidebarModel.groups().first { $0.section == .world }
        )
        let descriptor = try #require(
            worldGroup.destinations.first { $0.id == "scripts" }
        )
        #expect(descriptor.sidebarIdentifier == "Destination-scripts")

        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("World > Scripts is not a world inspector")
            return
        }
        let context = WorldPanelContext(providers: providers)
        let panel = try #require(
            makePanel(context) as? ScriptsPanelViewController
        )
        panel.loadViewIfNeeded()
        panel.startInspecting()
        defer { panel.stopInspecting() }

        #expect(scriptsReadout("ScriptInstancesStatsLabel", in: panel.view)?
            .contains("Instances: 2") == true)
        #expect(scriptsReadout("ScriptEventsStatsLabel", in: panel.view)?
            .contains("OnActivate -> leverscript") == true)
        #expect(scriptsReadout("ScriptSchedulerStatsLabel", in: panel.view)?
            .contains("Pending timers: 1") == true)
        #expect(scriptsReadout("ScriptNativeTallyStatsLabel", in: panel.view)?
            .contains("Native calls: 3") == true)

        panel.scriptPauseControl.state = .on
        sendScriptsControl(panel.scriptPauseControl)
        sendScriptsControl(panel.scriptStepControl)
        sendScriptsControl(panel.scriptBurstControl)
        #expect(providers.scripts.setPausedCalls == [true])
        #expect(providers.scripts.stepCalls == [1, ScriptSchedulerSection.burstTicks])
        #expect(try #require(descriptor.overrides).isOverridden(context))

        descriptor.overrides?.resetToDefaults(context)
        panel.startInspecting()
        #expect(providers.scripts.setPausedCalls == [true, false])
        #expect(!panel.isOverridden)
        #expect(scriptsReadout("ScriptSchedulerStatsLabel", in: panel.view)?
            .contains("VM: running") == true)
    }
}
