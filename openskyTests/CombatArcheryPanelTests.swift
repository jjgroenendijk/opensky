// The Archery section of `World > Combat & Physics` (issue #196, roadmap
// item 15.5, scope point 6). Same panel and same fake as the Melee section
// beside it, asked the same three questions: does the readout describe the
// engine, does it say so when there is no engine, and does every control reach
// the provider.

import AppKit
@testable import opensky
import Testing

struct CombatArcheryPanelTests {
    /// Accessibility ids are the UI-test API (docs/tools/app-ui.md); pin the
    /// archery set literally, and check every control is laid out and visible.
    @Test @MainActor
    func accessibilityIdentifiersArePinnedAndControlsAreVisible() throws {
        let panel = CombatPhysicsPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 1800)
        panel.view.layoutSubtreeIfNeeded()

        #expect(panel.archerySection.sectionIdentifier == "combatArchery")
        #expect(panel.archerySpawnControl.accessibilityIdentifier() == "ArcherySpawnControl")
        #expect(
            panel.archerySection.despawnControl.accessibilityIdentifier()
                == "ArcheryDespawnControl"
        )
        #expect(
            panel.archerySection.clearStuckControl.accessibilityIdentifier()
                == "ArcheryClearStuckControl"
        )
        #expect(
            panel.archerySection.clearTraceControl.accessibilityIdentifier()
                == "ArcheryClearTraceControl"
        )
        #expect(scriptsReadout("CombatArcheryStatsLabel", in: panel.view) != nil)

        for control: NSView in [
            panel.archerySpawnControl,
            panel.archerySection.despawnControl,
            panel.archerySection.clearStuckControl,
            panel.archerySection.clearTraceControl
        ] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            #expect(control.isDescendant(of: scrollView))
        }
    }

    /// The readout carries the three things scope point 6 names — spawn point,
    /// impact point and flight time — plus the live count and the equipment
    /// behind the shot.
    @Test @MainActor
    func archeryReadoutDescribesTheShotAndTheLastTrajectory() throws {
        let providers = FakeWorldProviders()
        providers.archery.snapshot = Self.snapshot()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("CombatArcheryStatsLabel", in: panel.view))
        #expect(readout.contains("shot drawn"))
        #expect(readout.contains("arrow nocked"))
        #expect(readout.contains("LongBow"))
        #expect(readout.contains("IronArrow"))
        #expect(readout.contains("ArrowIronProjectile"))
        #expect(readout.contains("gravity x0.350"))
        #expect(readout.contains("2 fired, 1 impacts, 1 in flight, 3 stuck"))
        // Spawn point, impact point, flight time.
        #expect(readout.contains("(0, 0, 128)"))
        #expect(readout.contains("(1200, 0, 109)"))
        #expect(readout.contains("0.33s"))
        #expect(readout.contains("stuck"))
    }

    /// With no runtime attached the section says so rather than showing a
    /// convincing zero.
    @Test @MainActor
    func archeryReadoutSaysWhenNoRuntimeIsAttached() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("CombatArcheryStatsLabel", in: panel.view))
        #expect(readout.contains("Archery: unavailable"))
    }

    @Test @MainActor
    func everyArcheryControlReachesTheProvider() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)

        sendScriptsControl(panel.archerySpawnControl)
        #expect(providers.archery.spawnRequests == 1)

        sendScriptsControl(panel.archerySection.despawnControl)
        #expect(providers.archery.despawnRequests == 1)

        sendScriptsControl(panel.archerySection.clearStuckControl)
        #expect(providers.archery.stuckClearRequests == 1)

        sendScriptsControl(panel.archerySection.clearTraceControl)
        #expect(providers.archery.traceClearCount == 1)
    }

    // MARK: - Fixture

    /// A session mid-draw with one arrow still in the air and one shot behind
    /// it that stuck in a wall.
    private static func snapshot() -> ArcherySnapshot {
        ArcherySnapshot(
            isAvailable: true,
            phase: .drawn,
            hasArrowAttached: true,
            heldSeconds: 1.4,
            lastHeldSeconds: 1.2,
            drawFraction: 1,
            bowName: "LongBow",
            bowDamage: 6,
            bowSpeed: 1,
            arrowName: "IronArrow",
            arrowDamage: 8,
            projectileName: "ArrowIronProjectile",
            projectileSpeed: 3600,
            projectileGravityFactor: 0.35,
            projectileRange: 60000,
            drawRequestCount: 3,
            firedCount: 2,
            impactCount: 1,
            liveCount: 1,
            stuckCount: 3,
            trace: [ProjectileTraceReadout(
                id: 4,
                launch: SIMD3(0, 0, 128),
                end: SIMD3(1200, 0, 109),
                flightTime: 0.333,
                travelled: 1200,
                drop: 19,
                outcome: .hitStatic,
                target: nil,
                appliedDamage: 0,
                sound: "skyrim.esm:0004FE",
                stuck: true
            )],
            settings: ["fVisibleNavmeshMoveDist = 4096.000 [UESP-documented default]"]
        )
    }

    @MainActor
    private static func panel(
        providers: FakeWorldProviders
    ) throws -> CombatPhysicsPanelViewController {
        let descriptor = try #require(DestinationRegistry.destination(id: "combatPhysics"))
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("combatPhysics is not a world inspector")
            throw CombatArcheryPanelTestError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? CombatPhysicsPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }
}

private enum CombatArcheryPanelTestError: Error {
    case notAWorldInspector
}
