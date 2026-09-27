// M14 milestone panel acceptance (issue #191): one uninterrupted run through
// the real sidebar model and the registry-built World > Player & Locomotion
// panel on a single provider set, in the M10-M13 acceptance-triad shape.
//
// The readouts are found by their accessibility identifiers, which is the
// deterministic substitute while UI automation is TCC-blocked
// (docs/tools/environment.md). `PlayerLocomotionPanelTests` covers each section
// on its own; what this adds is that the whole destination works as one
// surface, in the order a session would use it, without a single fake being
// swapped halfway.

import AppKit
@testable import opensky
import simd
import Testing

@MainActor
struct M14AcceptancePanelTests {
    @Test
    func locomotionDestinationRunsTheWholeAcceptanceFlow() throws {
        let providers = FakeWorldProviders()
        providers.locomotion.status = Self.runningStatus()
        providers.locomotion.activeStates = [Self.activeState]
        providers.locomotion.variables = Self.variables
        providers.locomotion.tally = BehaviorTally()

        let panel = try Self.buildPanel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        Self.startTheSimulation(panel, providers: providers)
        Self.expectReadouts(panel)
        Self.driveTheBindings(panel, providers: providers)
        try Self.forceAStateAndReleaseIt(panel, providers: providers)
    }

    // MARK: - The run

    /// The sidebar row and the registry factory, taken through the same path
    /// the app takes rather than by constructing the panel directly.
    private static func buildPanel(
        providers: FakeWorldProviders
    ) throws -> PlayerLocomotionPanelViewController {
        let worldGroup = try #require(
            AppSidebarModel.groups().first { $0.section == .world }
        )
        let descriptor = try #require(
            worldGroup.destinations.first { $0.id == "playerLocomotion" }
        )
        #expect(descriptor.sidebarIdentifier == "Destination-playerLocomotion")
        #expect(descriptor.title == "Player & Locomotion")

        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("World > Player & Locomotion is not a world inspector")
            throw M14PanelAcceptanceError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? PlayerLocomotionPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    /// Step 1 — the session starts in fly mode, where no player is simulated,
    /// and the panel's own camera control is what starts one.
    private static func startTheSimulation(
        _ panel: PlayerLocomotionPanelViewController,
        providers: FakeWorldProviders
    ) {
        #expect(providers.movementMode == .fly)
        #expect(
            scriptsReadout("LocomotionStateStatsLabel", in: panel.view)?
                .contains("Camera: fly") == true
        )

        panel.cameraModeControl.selectItem(at: 1)
        sendScriptsControl(panel.cameraModeControl)
        #expect(providers.movementMode == .walk)
        panel.startInspecting()
    }

    /// Every readout the destination publishes, read back by accessibility id.
    /// A session running on solid ground with a graph attached has to be
    /// legible in all five.
    private static func expectReadouts(_ panel: PlayerLocomotionPanelViewController) {
        #expect(scriptsReadout("LocomotionStateStatsLabel", in: panel.view)?
            .contains("Gait: run  Motion: configured speed") == true)
        #expect(scriptsReadout("LocomotionGraphStatsLabel", in: panel.view)?
            .contains("MTState > Sprint") == true)
        #expect(scriptsReadout("LocomotionGraphStatsLabel", in: panel.view)?
            .contains("Speed = 360.000") == true)
        #expect(scriptsReadout("LocomotionBindingsStatsLabel", in: panel.view)?
            .contains("Sneak — C (toggle)") == true)
        #expect(scriptsReadout("LocomotionMotionStatsLabel", in: panel.view)?
            .contains("Travel: root motion 0.0 u") == true)
        #expect(scriptsReadout("LocomotionDevStatsLabel", in: panel.view)?
            .contains("Forced gait: none") == true)
    }

    /// Step 2 — the bindings, in the order a session uses them: crouch, stand
    /// up, jump, and raise the landing event by hand.
    private static func driveTheBindings(
        _ panel: PlayerLocomotionPanelViewController,
        providers: FakeWorldProviders
    ) {
        panel.sneakControl.state = .on
        sendScriptsControl(panel.sneakControl)
        #expect(providers.isSneaking)
        #expect(scriptsReadout("LocomotionBindingsStatsLabel", in: panel.view)?
            .contains("Sneak — C (toggle)  active") == true)

        panel.sneakControl.state = .off
        sendScriptsControl(panel.sneakControl)
        #expect(!providers.isSneaking)

        sendScriptsControl(panel.jumpControl)
        #expect(providers.locomotion.jumpRequests == 1)

        panel.devSection.eventControl.stringValue = LocomotionGraphNames.jumpLand
        sendScriptsControl(panel.raiseEventControl)
        #expect(providers.locomotion.raisedEvents == [LocomotionGraphNames.jumpLand])
    }

    /// Step 3 — the dev control and the destination's override policy with it:
    /// a held gait is the override, driving a binding is not, and the sidebar's
    /// reset releases the gait without undoing a single world action.
    private static func forceAStateAndReleaseIt(
        _ panel: PlayerLocomotionPanelViewController,
        providers: FakeWorldProviders
    ) throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "playerLocomotion"))
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(descriptor.overrides)
        #expect(!overrides.isOverridden(context), "driving a binding must not light the dot")

        panel.forcedGaitControl.selectItem(at: 5)
        sendScriptsControl(panel.forcedGaitControl)
        #expect(providers.forcedLocomotionGait == .swim)
        #expect(overrides.isOverridden(context))
        panel.startInspecting()
        #expect(scriptsReadout("LocomotionDevStatsLabel", in: panel.view)?
            .contains("Forced gait: swim") == true)

        sendScriptsControl(panel.clearTraceControl)
        #expect(providers.locomotion.traceClearCount == 1)

        // The sidebar's own reset, not the panel's Clear button: it is the
        // registry contract that has to release the gait.
        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        panel.startInspecting()
        #expect(scriptsReadout("LocomotionDevStatsLabel", in: panel.view)?
            .contains("Forced gait: none") == true)
        // The jump the user asked for survived the reset, which is the whole
        // point of keeping world actions out of the override.
        #expect(providers.locomotion.jumpRequests == 1)
    }

    // MARK: - Fixtures

    /// The session the readouts describe: running on solid ground, with the
    /// graph blending out of a sprint.
    private static func runningStatus() -> LocomotionStatus {
        var status = LocomotionStatus(graphAvailable: true, firstPersonGraphAvailable: true)
        var plan = LocomotionStepPlan()
        plan.horizontalDisplacement = SIMD2<Float>(3, 0)
        plan.motionSource = .configuredSpeed
        status.update(
            gait: .run,
            plan: plan,
            state: LocomotionStepState(
                feetPosition: SIMD3<Float>(100, 200, 0),
                verticalVelocity: 0,
                isGrounded: true,
                yaw: 0,
                dt: 1 / 120
            ),
            waterSurface: nil
        )
        status.noteEventRaised(LocomotionGraphNames.moveStart)
        status.noteEventRaised(LocomotionGraphNames.sprintStop)
        return status
    }

    private static let activeState = BehaviorActiveState(
        machineName: "MTState",
        stateId: 3,
        stateName: "Sprint",
        previousStateName: "Run",
        blendWeight: 1
    )

    private static let variables = [
        LocomotionVariableSnapshot(name: LocomotionGraphNames.speed, value: "360.000"),
        LocomotionVariableSnapshot(name: LocomotionGraphNames.isSprinting, value: "false")
    ]
}

/// Thrown only to end the run early when the registry hands back something
/// other than a world inspector, which `Issue.record` has already reported.
private enum M14PanelAcceptanceError: Error {
    case notAWorldInspector
}
