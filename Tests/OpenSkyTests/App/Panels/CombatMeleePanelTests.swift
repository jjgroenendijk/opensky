// The Melee section of `World > Combat & Physics`, split for the type-body
// cap. Does the readout describe the engine, say so when there is none, and
// does every control reach the provider?

import AppKit
@testable import OpenSky
@testable import OpenSkyActorsInterface
@testable import OpenSkyCombat
import Testing

struct CombatMeleePanelTests {
    /// Accessibility ids are the UI-test API (docs/tools/app-ui.md); pin the
    /// melee set literally, and check every control is laid out and visible.
    @Test @MainActor
    func accessibilityIdentifiersArePinnedAndControlsAreVisible() throws {
        let panel = CombatPhysicsPanelViewController()
        let scrollView = try #require(panel.view as? NSScrollView)
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 1400)
        panel.view.layoutSubtreeIfNeeded()

        #expect(panel.meleeSection.sectionIdentifier == "combatMelee")
        #expect(
            panel.weaponDrawnControl.accessibilityIdentifier() == "MeleeWeaponDrawnControl"
        )
        #expect(panel.attackControl.accessibilityIdentifier() == "MeleeAttackControl")
        #expect(
            panel.meleeSection.clearTraceControl.accessibilityIdentifier()
                == "MeleeClearTraceControl"
        )
        #expect(scriptsReadout("CombatMeleeStatsLabel", in: panel.view) != nil)

        for control: NSView in [
            panel.weaponDrawnControl, panel.attackControl,
            panel.meleeSection.clearTraceControl
        ] {
            #expect(!control.isHidden)
            #expect(control.frame.height > 0)
            #expect(control.isDescendant(of: scrollView))
        }
    }

    /// The Melee readout names where the weapon is, what it is, its reach, and
    /// the last hit.
    @Test @MainActor
    func meleeReadoutDescribesTheWeaponAndTheLastHit() throws {
        let providers = FakeWorldProviders()
        providers.melee.snapshot = Self.meleeSnapshot()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("CombatMeleeStatsLabel", in: panel.view))
        #expect(readout.contains("weapon drawn"))
        #expect(readout.contains("attack contact"))
        #expect(readout.contains("blocking"))
        #expect(readout.contains("IronSword"))
        #expect(readout.contains("99 units"))
        #expect(readout.contains("Hits: 1 of 2 swings"))
        #expect(readout.contains("blocked 33%"))
        #expect(readout.contains("staggered"))
    }

    /// With no runtime attached the section says so rather than showing a
    /// convincing zero.
    @Test @MainActor
    func meleeReadoutSaysWhenNoRuntimeIsAttached() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let readout = try #require(scriptsReadout("CombatMeleeStatsLabel", in: panel.view))
        #expect(readout.contains("Melee: no game loaded"))
    }

    /// Both melee controls reach the provider, and the checkbox reflects it.
    @Test @MainActor
    func meleeControlsRoundTripThroughTheProvider() throws {
        let providers = FakeWorldProviders()
        let panel = try Self.panel(providers: providers)

        panel.weaponDrawnControl.state = .on
        sendScriptsControl(panel.weaponDrawnControl)
        #expect(providers.melee.isWeaponDrawn)
        panel.weaponDrawnControl.state = .off
        sendScriptsControl(panel.weaponDrawnControl)
        #expect(!providers.melee.isWeaponDrawn)

        sendScriptsControl(panel.attackControl)
        #expect(providers.melee.attackRequests == 1)

        sendScriptsControl(panel.meleeSection.clearTraceControl)
        #expect(providers.melee.traceClearCount == 1)
    }

    // MARK: - Fixture

    /// A session mid-swing: sword drawn, on the contact frame, guard up, one
    /// blocked and staggering hit behind it.
    private static func meleeSnapshot() -> MeleeCombatSnapshot {
        MeleeCombatSnapshot(
            isAvailable: true,
            drawState: .drawn,
            attackPhase: .contact,
            isBlocking: true,
            isStaggering: false,
            weaponName: "IronSword",
            weaponDamage: 7,
            weaponReachMultiplier: 0.7,
            weaponSpeed: 1,
            rightHandType: .sword,
            leftHandType: .shield,
            reach: 98.7,
            swingCount: 2,
            hitCount: 1,
            trace: [MeleeHitReadout(
                target: "skyrim.esm:00A1B2",
                distance: 62,
                baseDamage: 7,
                blockedPercent: 32.6,
                appliedDamage: 4.7,
                sound: "skyrim.esm:0004FE",
                staggered: true
            )],
            settings: ["fCombatDistance = 141.000 [Skyrim.esm]"]
        )
    }

    @MainActor
    private static func panel(
        providers: FakeWorldProviders
    ) throws -> CombatPhysicsPanelViewController {
        let descriptor = try #require(DestinationRegistry.destination(id: "combatPhysics"))
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("combatPhysics is not a world inspector")
            throw CombatMeleePanelTestError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers))
                as? CombatPhysicsPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }
}

private enum CombatMeleePanelTestError: Error {
    case notAWorldInspector
}
