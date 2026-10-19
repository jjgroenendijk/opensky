// World > AI & Navigation: the Behaviour Graphs section, the script package controls of
// the Package section, and the Confidence and Assistance switch of the Combat Loop section.
// Ids are the UI-test API (docs/tools/app-ui.md), so they are pinned as literals.

import AppKit
@testable import OpenSky
@testable import OpenSkyActorPresentation
@testable import OpenSkyAIPackages
@testable import OpenSkyCombat
@testable import OpenSkyFormatsESM
import Testing

@MainActor
struct AIBehaviorGraphPanelTests {
    private static let actor = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x500)

    private func panel(_ providers: FakeWorldProviders) throws -> AINavigationPanelViewController {
        let panel = try buildWorldPanel(
            "aiNavigation", title: "AI & Navigation", providers: providers
        ) as AINavigationPanelViewController
        panel.view.frame = NSRect(x: 0, y: 0, width: 300, height: 4000)
        panel.view.layoutSubtreeIfNeeded()
        return panel
    }

    @Test func theGraphSectionIsWiredAndItsIdsArePinned() throws {
        let providers = FakeWorldProviders()
        let panel = try panel(providers)
        let section = panel.graphSection
        #expect(section.provider === providers)
        #expect(section.sectionIdentifier == "aiBehaviorGraphs")
        let ids: [(NSView, String)] = [
            (section.enabledControl, "ActorGraphEnabledControl"),
            (section.fullRateControl, "ActorGraphFullRateControl"),
            (section.distanceControl, "ActorGraphDistanceControl"),
            (section.eventControl, "ActorGraphEventControl"),
            (section.sendControl, "ActorGraphSendControl"),
            (panel.packageSection.scriptPackageControl, "AIScriptPackageControl"),
            (panel.packageSection.addScriptPackageControl, "AIAddScriptPackageControl"),
            (panel.packageSection.removeScriptPackageControl, "AIRemoveScriptPackageControl")
        ]
        for (control, identifier) in ids {
            #expect(control.accessibilityIdentifier() == identifier)
        }
        #expect(scriptsReadout("ActorGraphStatsLabel", in: panel.view) != nil)
    }

    @Test func theSwitchAndTheCutoffReachTheProvider() throws {
        let providers = FakeWorldProviders()
        let section = try panel(providers).graphSection
        section.enabledControl.state = .off
        sendScriptsControl(section.enabledControl)
        #expect(!providers.actorGraphState.snapshot.isEnabled)
        #expect(section.isOverridden)

        section.fullRateControl.floatValue = 1024
        section.distanceControl.floatValue = 4096
        sendScriptsControl(section.distanceControl)
        #expect(providers.actorGraphState.snapshot.cutoff == ActorGraphCutoff(
            fullRateDistance: 1024, maximumDistance: 4096
        ))

        AIBehaviorGraphSection.resetToDefaults(provider: providers)
        #expect(providers.actorGraphState.snapshot.isEnabled)
        #expect(providers.actorGraphState.snapshot.cutoff == .standard)
    }

    @Test func theReadoutShowsTheSelectedActorsStatesAndEvents() {
        let snapshot = ActorGraphControlSnapshot(
            isEnabled: true, cutoff: .standard, runningCount: 3, fullRateCount: 2,
            reducedRateCount: 1, failures: [],
            selected: ActorGraphReadout(
                actor: Self.actor, project: "meshes\\actors\\canine\\wolfproject.hkx",
                activeStates: ["Root", "Locomotion"], recentEvents: ["FootLeft", "FootRight"],
                steps: 12, rate: .full
            )
        )
        let lines = ActorGraphReadoutText.lines(for: snapshot)
        #expect(lines.contains("Running: 3"))
        #expect(lines.contains("States: Root > Locomotion"))
        #expect(lines.contains("Events: FootLeft, FootRight"))
    }

    @Test func theScriptPackageControlsReachTheProvider() throws {
        let providers = FakeWorldProviders()
        let section = try panel(providers).packageSection
        section.scriptPackageControl.stringValue = " MQ07BeggarToTavern "
        sendScriptsControl(section.addScriptPackageControl)
        sendScriptsControl(section.removeScriptPackageControl)
        #expect(providers.aiNavigation.scriptPackages == ["MQ07BeggarToTavern", nil])
    }

    @Test func theConfidenceSwitchReachesTheProvider() {
        let providers = FakeWorldProviders()
        let panel = CombatPhysicsPanelViewController()
        panel.combatProvider = providers
        _ = panel.view
        let control = panel.loopSection.temperamentControl
        #expect(control.accessibilityIdentifier() == "CombatTemperamentControl")
        control.state = .off
        sendScriptsControl(control)
        #expect(!providers.usesCombatTemperament)
    }

    @Test func theTemperamentReadoutNamesTheDecision() {
        var snapshot = CombatLoopSnapshot.unavailable
        #expect(CombatLoopReadout.temperamentText(for: snapshot) == "Confidence: unavailable")
        snapshot = CombatLoopSnapshot(
            isAvailable: true, isPlayerInCombat: false, targetName: "—", targetDistance: 0,
            hostileCount: 0, deadCount: 0, engagedCount: 0, searchingCount: 0, actors: [],
            crowdedOutCount: 0, selectedActorName: "Wolf", selectedActorIsHostile: true,
            incomingHitCount: 0, incomingTrace: [], damageFlash: 0, transients: .none,
            limits: .standard, trimmedTransients: .none, isActorCastingEnabled: true,
            actorCastCount: 0, lastActionText: ""
        )
        snapshot.selectedTemperament = CombatTemperament(confidence: 0, strengthRatio: 2)
        snapshot.selectedAssistance = .helpsAllies
        let text = CombatLoopReadout.temperamentText(for: snapshot)
        #expect(text.contains("cowardly"))
        #expect(text.contains("would flee"))
        #expect(text.contains("helps allies"))
    }
}
