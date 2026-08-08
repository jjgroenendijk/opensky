// The Death & Ragdoll section of `World > Combat & Physics` (issue #197,
// roadmap item 15.6, scope point 7). Same panel and same fake as the Melee and
// Archery sections beside it, asked the same three questions: does the readout
// describe the engine, does it say so when there is no engine, and does every
// control reach the provider.

import AppKit
@testable import opensky
import Testing

struct CombatRagdollPanelTests {
    /// Accessibility ids are the UI-test API (docs/tools/app-ui.md); pin the
    /// ragdoll set literally, and check every control is laid out and visible.
    @Test @MainActor
    func accessibilityIdentifiersArePinnedAndControlsAreVisible() throws {
        let panel = CombatPhysicsPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 2200)
        panel.view.layoutSubtreeIfNeeded()

        #expect(panel.ragdollSection.sectionIdentifier == "combatRagdoll")
        #expect(
            panel.ragdollSection.triggerControl.accessibilityIdentifier()
                == "RagdollTriggerControl"
        )
        #expect(
            panel.ragdollSection.clearControl.accessibilityIdentifier()
                == "RagdollClearControl"
        )
        #expect(
            panel.ragdollSection.freezeControl.accessibilityIdentifier()
                == "RagdollFreezeControl"
        )
        #expect(scriptsReadout("CombatRagdollStatsLabel", in: panel.view) != nil)

        for control: NSView in [
            panel.ragdollSection.triggerControl,
            panel.ragdollSection.clearControl,
            panel.ragdollSection.freezeControl
        ] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            #expect(control.isDescendant(of: scrollView))
        }
    }

    /// The readout carries the two things scope point 7 names — the bone-body
    /// count and the constraint iteration count — plus how many corpses are
    /// simulating and whether the solver converged.
    @Test @MainActor
    func ragdollReadoutDescribesTheBodiesAndTheSolver() throws {
        let providers = FakeWorldProviders()
        providers.ragdoll.snapshot = RagdollStatsSnapshot(
            ragdollCount: 3,
            activeRagdollCount: 1,
            settledRagdollCount: 2,
            boneBodyCount: 54,
            jointCount: 51,
            jointViolationCount: 2
        )
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("CombatRagdollStatsLabel", in: panel.view))
        #expect(readout.contains("Ragdolls: 3 (1 active, 2 settled)"))
        #expect(readout.contains("Bone bodies: 54 over 51 joints"))
        #expect(readout.contains("\(RagdollConstraintSolver.iterationCount) iterations/substep"))
        #expect(readout.contains("2 limits still violated"))
        #expect(readout.contains("no pose recovery needed"))
    }

    /// A settled world reads as converged rather than as a bare zero.
    @Test @MainActor
    func aConvergedSolverSaysSo() throws {
        let providers = FakeWorldProviders()
        providers.ragdoll.snapshot = RagdollStatsSnapshot(ragdollCount: 1, boneBodyCount: 18)
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("CombatRagdollStatsLabel", in: panel.view))
        #expect(readout.contains("converged"))
        #expect(!readout.contains("still violated"))
    }

    /// With nothing dead the section says so rather than showing a convincing
    /// zero.
    @Test @MainActor
    func ragdollReadoutSaysWhenNothingIsSimulating() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("CombatRagdollStatsLabel", in: panel.view))
        #expect(readout.contains("Ragdolls: none"))
    }

    @Test @MainActor
    func everyRagdollControlReachesTheProvider() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)

        sendScriptsControl(panel.ragdollSection.triggerControl)
        #expect(providers.ragdoll.triggerRequests == 1)

        sendScriptsControl(panel.ragdollSection.clearControl)
        #expect(providers.ragdoll.clearRequests == 1)

        panel.ragdollSection.freezeControl.state = .on
        sendScriptsControl(panel.ragdollSection.freezeControl)
        #expect(providers.ragdoll.snapshot.isFrozen)

        panel.ragdollSection.freezeControl.state = .off
        sendScriptsControl(panel.ragdollSection.freezeControl)
        #expect(!providers.ragdoll.snapshot.isFrozen)
    }

    // MARK: - Fixture

    @MainActor
    private static func panel(
        providers: FakeWorldProviders
    ) throws -> CombatPhysicsPanelViewController {
        let descriptor = try #require(DestinationRegistry.destination(id: "combatPhysics"))
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("combatPhysics is not a world inspector")
            throw CombatRagdollPanelTestError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? CombatPhysicsPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }
}

private enum CombatRagdollPanelTestError: Error {
    case notAWorldInspector
}
