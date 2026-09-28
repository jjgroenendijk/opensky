// M16 milestone panel acceptance (issue #203): one uninterrupted run through
// the real sidebar model and the registry-built World > AI & Navigation panel on
// a single provider set, in the M10-M15 acceptance-triad shape.
//
// The readouts are found by their accessibility identifiers, which is the
// deterministic substitute while UI automation is TCC-blocked
// (docs/tools/environment.md). What this adds over the section suites is that
// the whole destination works as one surface, in the order a session would use
// it — switch on the overlays, choose an actor, send it somewhere, read its
// package, read what it perceives, make it hostile — without a single fake being
// swapped halfway.

import AppKit
@testable import opensky
import simd
import Testing

@MainActor
struct M16AcceptancePanelTests {
    @Test
    func theAIDestinationRunsTheWholeAcceptanceFlow() throws {
        let providers = FakeWorldProviders()
        providers.aiNavigation.snapshot = Self.navigation
        providers.perception.snapshot = Self.perception
        providers.perception.lines = [Self.guardKey: [Self.detectionLine]]
        providers.combatLoop.snapshot = Self.combat

        let panel = try Self.buildPanel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        Self.expectEveryReadout(panel)
        Self.selectAnActor(panel, providers: providers)
        Self.sendItSomewhere(panel, providers: providers)
        Self.readItsScheduleAndAngerIt(panel, providers: providers)
        try Self.switchTheOverlaysOnAndResetThem(panel, providers: providers)
    }

    // MARK: - The run

    /// The sidebar row and the registry factory, taken through the same path
    /// the app takes rather than by constructing the panel directly.
    private static func buildPanel(
        providers: FakeWorldProviders
    ) throws -> AINavigationPanelViewController {
        let worldGroup = try #require(
            AppSidebarModel.groups().first { $0.section == .world }
        )
        let descriptor = try #require(
            worldGroup.destinations.first { $0.id == "aiNavigation" }
        )
        #expect(descriptor.sidebarIdentifier == "Destination-aiNavigation")
        #expect(descriptor.title == "AI & Navigation")

        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("World > AI & Navigation is not a world inspector")
            throw M16PanelAcceptanceError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? AINavigationPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    /// Every readout the destination publishes, read back by accessibility id.
    /// A session mid-day has to be legible in all six.
    private static func expectEveryReadout(_ panel: AINavigationPanelViewController) {
        let view = panel.view
        #expect(scriptsReadout("AIOverlayStatsLabel", in: view)?
            .contains("Overlays: all off") == true)
        #expect(scriptsReadout("AIActorStatsLabel", in: view)?
            .contains("acting on Guard") == true)
        #expect(scriptsReadout("AIMovementStatsLabel", in: view)?
            .contains("Movement: Guard moving") == true)
        #expect(scriptsReadout("AIPackageStatsLabel", in: view)?
            .contains("M16GuardPatrol") == true)
        #expect(scriptsReadout("DetectionStatsLabel", in: view)?
            .contains(detectionLine) == true)
        #expect(scriptsReadout("DetectionSettingsStatsLabel", in: view)?
            .contains("fDetectionViewCone = 190.000 [Skyrim.esm]") == true)
        #expect(scriptsReadout("AICombatStatsLabel", in: view)?
            .contains("Selected: Guard is hostile") == true)
    }

    /// Step 1 — the selection, which is what every other section answers for.
    /// Both routes are exercised: the popup and the crosshair pick.
    private static func selectAnActor(
        _ panel: AINavigationPanelViewController,
        providers: FakeWorldProviders
    ) {
        #expect(panel.actorSelectControl.numberOfItems == 2)
        panel.actorSelectControl.selectItem(at: 1)
        sendScriptsControl(panel.actorSelectControl)
        #expect(providers.selectedAIActor == secondKey)

        sendScriptsControl(panel.actorCrosshairControl)
        #expect(providers.aiNavigation.crosshairSelectCount == 1)
    }

    /// Step 2 — the move-to-point dev control and its counterpart.
    private static func sendItSomewhere(
        _ panel: AINavigationPanelViewController,
        providers: FakeWorldProviders
    ) {
        sendScriptsControl(panel.moveToCrosshairControl)
        #expect(providers.aiNavigation.moveRequestCount == 1)

        sendScriptsControl(panel.moveStopControl)
        #expect(providers.aiNavigation.stopRequestCount == 1)
    }

    /// Step 3 — the package reevaluation and the hostility toggle: the two
    /// things this destination can actually change about an actor's day.
    private static func readItsScheduleAndAngerIt(
        _ panel: AINavigationPanelViewController,
        providers: FakeWorldProviders
    ) {
        sendScriptsControl(panel.packageReevaluateControl)
        #expect(providers.aiNavigation.reevaluateCount == 1)

        panel.hostilityControl.state = .on
        sendScriptsControl(panel.hostilityControl)
        #expect(providers.selectedAIActorIsHostile)
    }

    /// Step 4 — the destination's override policy: following an actor and
    /// angering it are not overrides, three debug overlays that default off
    /// are, and the sidebar's own reset switches them back without undoing a
    /// single thing the session did to the world.
    private static func switchTheOverlaysOnAndResetThem(
        _ panel: AINavigationPanelViewController,
        providers: FakeWorldProviders
    ) throws {
        let descriptor = try #require(DestinationRegistry.destination(id: "aiNavigation"))
        let context = WorldPanelContext(providers: providers)
        let overrides = try #require(descriptor.overrides)
        #expect(!overrides.isOverridden(context), "following an actor must not light the dot")

        panel.navmeshOverlayControl.state = .on
        sendScriptsControl(panel.navmeshOverlayControl)
        panel.pathOverlayControl.state = .on
        sendScriptsControl(panel.pathOverlayControl)
        panel.detectionOverlayControl.state = .on
        sendScriptsControl(panel.detectionOverlayControl)
        #expect(providers.navmeshOverlayEnabled)
        #expect(providers.pathOverlayEnabled)
        #expect(providers.detectionOverlayEnabled)
        #expect(overrides.isOverridden(context))
        panel.startInspecting()
        #expect(scriptsReadout("AIOverlayStatsLabel", in: panel.view)?
            .contains("navmesh, path, detection") == true)

        // The sidebar's own reset, not the panel's checkboxes: it is the
        // registry contract that has to switch them off.
        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        // Everything the session did to the world survived it.
        #expect(providers.aiNavigation.moveRequestCount == 1)
        #expect(providers.selectedAIActorIsHostile)
        #expect(providers.aiNavigation.reevaluateCount == 1)
    }

    // MARK: - Fixtures

    private static let guardKey = ReferenceKey.generated(1)
    private static let secondKey = ReferenceKey.generated(2)

    private static let detectionLine =
        "Guard -> Player: detected, level 100, value 4.0, 80 units, in sight,"
            + " last seen (480, 20, 0)"

    /// The session the readouts describe: two residents, the nearer one walking
    /// a corridor under a patrol package, with the crosshair on a point.
    private static let navigation = AINavigationSnapshot(
        isAvailable: true,
        actors: [
            AIActorOption(key: guardKey, name: "Guard", distance: 120, isDead: false),
            AIActorOption(key: secondKey, name: "Innkeeper", distance: 340, isDead: false)
        ],
        selectedActor: guardKey,
        selectedActorName: "Guard",
        movement: NPCMovementReadout(
            actor: guardKey,
            state: .moving,
            feetPosition: SIMD3(420, 20, 0),
            yaw: 0,
            waypointIndex: 2,
            waypointCount: 5,
            gait: .walk,
            repathCount: 0
        ),
        moverCount: 1,
        moverLimit: NPCMovementRuntime.maximumSimultaneousMovers,
        package: PackageActorReadout(
            actor: guardKey,
            actorBase: FormID(0x600),
            currentPackage: FormID(0x100),
            editorID: "M16GuardPatrol",
            schedule: Package.Schedule(
                month: -1, dayOfWeek: -1, date: 0, hour: 8, minute: 0, durationMinutes: 720
            ),
            procedure: .travel,
            lastEvaluationGameSeconds: 32400
        ),
        packagedActorCount: 2,
        crosshairPoint: SIMD3(560, 20, 0),
        selectedActorIsHostile: true,
        lastActionText: "Move: Guard is pathing to the crosshair point."
    )

    private static let perception = PerceptionControlSnapshot(
        readout: PerceptionReadout(
            pairs: [],
            observerCount: 2,
            targetCount: 1,
            droppedPairCount: 0,
            lineOfSightQueryCount: 2,
            stepCount: 120
        ),
        settings: [DetectionSettingReadout(
            editorID: "fDetectionViewCone", value: 190, source: "Skyrim.esm"
        )]
    )

    private static let combat = CombatLoopSnapshot(
        isAvailable: true,
        isPlayerInCombat: true,
        targetName: "Guard",
        targetDistance: 80,
        hostileCount: 1,
        deadCount: 0,
        engagedCount: 1,
        searchingCount: 0,
        actors: [CombatActorReadout(
            key: guardKey,
            name: "Guard",
            phase: .approaching,
            awareness: .detected,
            distance: 80,
            healthFraction: 1,
            attackCount: 0,
            contactCount: 0,
            blockCount: 0,
            searchCount: 0
        )],
        crowdedOutCount: 0,
        selectedActorName: "Guard",
        selectedActorIsHostile: true,
        incomingHitCount: 0,
        incomingTrace: [],
        damageFlash: 0,
        transients: .none,
        limits: .standard,
        trimmedTransients: .none,
        isActorCastingEnabled: true,
        actorCastCount: 0,
        lastActionText: "Hostility: Guard is now hostile."
    )
}

/// Thrown only to end the run early when the registry hands back something
/// other than a world inspector, which `Issue.record` has already reported.
private enum M16PanelAcceptanceError: Error {
    case notAWorldInspector
}
