// World > Player & Locomotion verification-surface coverage (issue #191): the
// panel the registry factory builds, the literal accessibility-id contract, the
// readouts each section renders from one snapshot, and the provider round trip
// for every control.
//
// Same shape as `JournalPanelTests`, which is the template the gate names.

import AppKit
@testable import opensky
import simd
import Testing

struct PlayerLocomotionPanelTests {
    @Test @MainActor
    func registryFactoryBuildsThePanelWithProvidersWired() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        #expect(panel.provider === providers)
        #expect(panel.stateSection.cameraProvider === providers)
    }

    /// Accessibility ids are the UI-test API (docs/tools/app-ui.md); pin the
    /// locomotion set literally.
    @Test @MainActor
    func accessibilityIdentifiersArePinned() {
        let panel = PlayerLocomotionPanelViewController()
        panel.loadViewIfNeeded()
        #expect(panel.stateSection.sectionIdentifier == "locomotionState")
        #expect(panel.graphSection.sectionIdentifier == "locomotionGraph")
        #expect(panel.bindingsSection.sectionIdentifier == "locomotionBindings")
        #expect(panel.motionSection.sectionIdentifier == "locomotionMotion")
        #expect(panel.devSection.sectionIdentifier == "locomotionDev")

        #expect(
            panel.cameraModeControl.accessibilityIdentifier() == "LocomotionCameraModeControl"
        )
        #expect(panel.sneakControl.accessibilityIdentifier() == "LocomotionSneakControl")
        #expect(panel.jumpControl.accessibilityIdentifier() == "LocomotionJumpControl")
        #expect(
            panel.clearTraceControl.accessibilityIdentifier() == "LocomotionTraceClearControl"
        )
        #expect(
            panel.forcedGaitControl.accessibilityIdentifier() == "LocomotionForcedGaitControl"
        )
        #expect(
            panel.devSection.clearForcedGaitControl.accessibilityIdentifier()
                == "LocomotionClearForcedGaitControl"
        )
        #expect(panel.devSection.eventControl.accessibilityIdentifier() == "LocomotionEventControl")
        #expect(
            panel.raiseEventControl.accessibilityIdentifier() == "LocomotionRaiseEventControl"
        )

        for identifier in [
            "LocomotionStateStatsLabel", "LocomotionGraphStatsLabel",
            "LocomotionBindingsStatsLabel", "LocomotionMotionStatsLabel",
            "LocomotionDevStatsLabel"
        ] {
            #expect(scriptsReadout(identifier, in: panel.view) != nil, "\(identifier) is missing")
        }
    }

    /// Layout invariant: no section control may be hidden or zero-height inside
    /// the panel's document view.
    @Test @MainActor
    func controlsHaveVisibleFramesInsideDocument() throws {
        let panel = PlayerLocomotionPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 1200)
        panel.view.layoutSubtreeIfNeeded()

        for control: NSView in [
            panel.cameraModeControl, panel.sneakControl, panel.jumpControl,
            panel.clearTraceControl, panel.forcedGaitControl,
            panel.devSection.clearForcedGaitControl, panel.devSection.eventControl,
            panel.raiseEventControl
        ] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            #expect(control.isDescendant(of: scrollView))
        }
    }

    // MARK: - Readouts

    /// The State readout names the gait, the motion source, the resolved gaits
    /// and where the walk number came from.
    @Test @MainActor
    func stateReadoutDescribesTheSimulatedPlayer() throws {
        let providers = FakeWorldProviders()
        providers.movementMode = .walk
        providers.locomotion.status = Self.status()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("LocomotionStateStatsLabel", in: panel.view))
        #expect(readout.contains("Gait: run"))
        #expect(readout.contains("Motion: configured speed"))
        #expect(readout.contains("Grounded: yes"))
        #expect(readout.contains("Swimming: no"))
        #expect(readout.contains("Gaits: walk 180.0"))
        #expect(readout.contains("Walk speed source: OpenSky synthetic"))
    }

    /// Fly mode says so rather than showing values that cannot move.
    @Test @MainActor
    func stateReadoutSaysWhenThePlayerIsNotSimulated() throws {
        let providers = FakeWorldProviders()
        providers.movementMode = .fly
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("LocomotionStateStatsLabel", in: panel.view))
        #expect(readout.contains("Camera: fly"))
    }

    /// The Behavior Graph readout carries the state path, the variables with
    /// their live values, a name the graph does not declare, and the tally.
    @Test @MainActor
    func graphReadoutShowsTheStatePathVariablesAndCoverage() throws {
        let providers = FakeWorldProviders()
        providers.movementMode = .walk
        providers.locomotion.status = Self.status()
        providers.locomotion.activeStates = [BehaviorActiveState(
            machineName: "MTState",
            stateId: 3,
            stateName: "Sprint",
            previousStateName: "Run",
            blendWeight: 0.5
        )]
        providers.locomotion.variables = [
            LocomotionVariableSnapshot(name: "Speed", value: "360.000"),
            LocomotionVariableSnapshot(name: "SpeedWalk", value: nil)
        ]
        providers.locomotion.tally = BehaviorTally()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("LocomotionGraphStatsLabel", in: panel.view))
        #expect(readout.contains("Behavior graph: attached"))
        #expect(readout.contains("MTState > Sprint  blending from Run at 0.5"))
        #expect(readout.contains("Speed = 360.000"))
        #expect(readout.contains("SpeedWalk = <not declared by the graph>"))
        #expect(readout.contains("Raised: moveStart"))
        #expect(readout.contains("Gaps: 0 total"))
    }

    /// The Root Motion readout keeps the two travel totals apart and lists the
    /// steps at which the source changed.
    @Test @MainActor
    func motionReadoutSeparatesTheTwoMotionSources() throws {
        let providers = FakeWorldProviders()
        providers.locomotion.status = Self.status()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("LocomotionMotionStatsLabel", in: panel.view))
        #expect(readout.contains("Travel: root motion 0.0 u"))
        #expect(readout.contains("configured speed 3.0 u"))
        #expect(readout.contains("run via configured speed"))
        // The rule the split is made by, so a zero root-motion total reads as
        // the expected answer rather than as a missing feature (issue #370).
        #expect(readout.contains("only for a clip whose data carries extracted motion"))
    }

    // MARK: - Controls

    /// Sneak is a toggle and jump is one action, both through the provider.
    @Test @MainActor
    func bindingControlsDriveTheProvider() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)

        panel.sneakControl.state = .on
        sendScriptsControl(panel.sneakControl)
        #expect(providers.isSneaking)
        panel.sneakControl.state = .off
        sendScriptsControl(panel.sneakControl)
        #expect(!providers.isSneaking)

        sendScriptsControl(panel.jumpControl)
        sendScriptsControl(panel.jumpControl)
        #expect(providers.locomotion.jumpRequests == 2)
    }

    /// The camera-mode popup lists the same three modes as `World > World` and
    /// sets the same renderer state.
    @Test @MainActor
    func cameraModeControlCyclesTheSameThreeModes() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        #expect(panel.cameraModeControl.numberOfItems == CameraMovementMode.allCases.count)

        panel.cameraModeControl.selectItem(at: 1)
        sendScriptsControl(panel.cameraModeControl)
        #expect(providers.movementMode == .walk)
        panel.cameraModeControl.selectItem(at: 2)
        sendScriptsControl(panel.cameraModeControl)
        #expect(providers.movementMode == .thirdPerson)
    }

    /// The forced-gait popup holds a gait, reports it, and gives it back.
    @Test @MainActor
    func forcedGaitControlHoldsAndReleasesTheGait() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        // Row 0 is "no forced gait", so the swim row is the last one.
        panel.forcedGaitControl.selectItem(at: 5)
        sendScriptsControl(panel.forcedGaitControl)
        #expect(providers.forcedLocomotionGait == .swim)
        #expect(
            scriptsReadout("LocomotionDevStatsLabel", in: panel.view)?
                .contains("Forced gait: swim") == true
        )

        sendScriptsControl(panel.devSection.clearForcedGaitControl)
        #expect(providers.forcedLocomotionGait == nil)
        #expect(panel.forcedGaitControl.indexOfSelectedItem == 0)
        #expect(
            scriptsReadout("LocomotionDevStatsLabel", in: panel.view)?
                .contains("Forced gait: none") == true
        )
    }

    /// Raising an event says whether the graph declared it, which is the whole
    /// point of the control: a name the data spells differently must not look
    /// like a successful poke.
    @Test @MainActor
    func raisingAnEventReportsWhetherTheGraphDeclaredIt() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        panel.devSection.eventControl.stringValue = LocomotionGraphNames.jumpLand
        sendScriptsControl(panel.raiseEventControl)
        #expect(providers.locomotion.raisedEvents == [LocomotionGraphNames.jumpLand])
        #expect(
            scriptsReadout("LocomotionDevStatsLabel", in: panel.view)?
                .contains("Last event: JumpLand raised") == true
        )

        panel.devSection.eventControl.stringValue = "NotAnEvent"
        sendScriptsControl(panel.raiseEventControl)
        #expect(
            scriptsReadout("LocomotionDevStatsLabel", in: panel.view)?
                .contains("the graph declares no such event") == true
        )
    }

    /// Clearing the trace is an action on the engine, not on the panel.
    @Test @MainActor
    func clearingTheTraceReachesTheProvider() throws {
        let providers = FakeWorldProviders()
        providers.locomotion.status = Self.status()
        let panel = try Self.panel(providers: providers)

        sendScriptsControl(panel.clearTraceControl)
        #expect(providers.locomotion.traceClearCount == 1)
        #expect(providers.locomotion.status.motionTrace.isEmpty)
        #expect(providers.locomotion.status.configuredSpeedDistance == 0)
    }

    // MARK: - Fixtures

    @MainActor
    private static func panel(
        providers: FakeWorldProviders
    ) throws -> PlayerLocomotionPanelViewController {
        let descriptor = try #require(DestinationRegistry.destination(id: "playerLocomotion"))
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("playerLocomotion is not a world inspector")
            throw PlayerLocomotionPanelTestError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? PlayerLocomotionPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    /// A session mid-run: running on solid ground under the configured gait,
    /// with one edge raised and three units of travel behind it.
    private static func status() -> LocomotionStatus {
        var status = LocomotionStatus(graphAvailable: true)
        var plan = LocomotionStepPlan()
        plan.horizontalDisplacement = SIMD2<Float>(3, 0)
        plan.motionSource = .configuredSpeed
        status.update(
            gait: .run,
            plan: plan,
            state: LocomotionStepState(
                feetPosition: SIMD3<Float>(10, 20, 30),
                verticalVelocity: 0,
                isGrounded: true,
                yaw: 0,
                dt: 1 / 120
            ),
            waterSurface: nil
        )
        status.noteEventRaised(LocomotionGraphNames.moveStart)
        return status
    }
}

private enum PlayerLocomotionPanelTestError: Error {
    case notAWorldInspector
}
