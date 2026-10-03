// M25 panel acceptance: World > AI & Navigation's Head Assembly and Idles
// sections on one provider set. Read the head part set, switch the head, list
// the cell's idle markers, play an idle, run a marker's pick, and reset.

import AppKit
@testable import OpenSky
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld
import TagsTesting
import Testing

@Suite(.tags(.acceptance))
@MainActor
struct CharacterIdleAcceptancePanelTests {
    private static let actor = ReferenceKey.generated(1)
    private static let markerKey = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x10)
    private static let lean = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x20)
    private static let wipe = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x21)

    @Test
    func theHeadAndIdleSectionsRunTheWholeFlow() throws {
        let providers = Self.providers()
        let panel: AINavigationPanelViewController = try buildWorldPanel(
            "aiNavigation", title: "AI & Navigation", providers: providers
        )
        panel.startInspecting()
        defer { panel.stopInspecting() }

        let markers = scriptsReadout("IdleMarkersLabel", in: panel.view)
        #expect(markers?.contains("Idle markers: 1, actors idling: 1") == true)
        #expect(markers?.contains("InnLeanMarker: 2 idles") == true)
        #expect(scriptsReadout("IdleStatsLabel", in: panel.view)?
            .contains("Pray: failed GetIsID") == true)
        #expect(scriptsReadout("HeadAssemblyStatsLabel", in: panel.view)?
            .contains("HairMaleNord01: hair, NPC choice") == true)

        panel.idleMarkerControl.selectItem(at: 0)
        sendScriptsControl(panel.idleMarkerControl)
        panel.idleSection.idleControl.selectItem(at: 1)
        sendScriptsControl(panel.idleSection.idleControl)
        sendScriptsControl(panel.idleFireControl)
        #expect(providers.idleState.fired.map(\.idle) == [Self.wipe])
        #expect(providers.idleState.fired.first?.actor == Self.actor)
        #expect(providers.idleState.fired.first?.ignoringConditions == false)
        sendScriptsControl(panel.idlePickControl)
        #expect(providers.idleState.picked.map(\.marker) == [Self.markerKey])

        panel.headSourceControl.selectItem(at: 1)
        sendScriptsControl(panel.headSourceControl)
        #expect(providers.idleState.headSources.map(\.0) == [.assembled])

        let descriptor = try #require(DestinationRegistry.destination(id: "aiNavigation"))
        let overrides = try #require(descriptor.overrides)
        let context = WorldPanelContext(providers: providers)
        #expect(!overrides.isOverridden(context))
        panel.idleMarkersControl.state = .off
        sendScriptsControl(panel.idleMarkersControl)
        #expect(overrides.isOverridden(context))
        overrides.resetToDefaults(context)
        #expect(!overrides.isOverridden(context))
        #expect(providers.idleState.snapshot.usesIdleMarkers)
    }

    private static func providers() -> FakeWorldProviders {
        let providers = FakeWorldProviders()
        providers.aiNavigation.snapshot = AINavigationSnapshot(
            isAvailable: true,
            actors: [AIActorOption(key: actor, name: "Innkeeper", distance: 80, isDead: false)],
            selectedActor: actor, selectedActorName: "Innkeeper", movement: nil,
            moverCount: 0, moverLimit: 8, package: nil, packagedActorCount: 0,
            crosshairPoint: nil, selectedActorIsHostile: false, lastActionText: ""
        )
        providers.idleState.snapshot = IdleControlSnapshot(
            isAvailable: true,
            usesIdleMarkers: true,
            markers: [IdleMarkerReadout(
                reference: markerKey, editorID: "InnLeanMarker", idles: ["Lean", "Wipe"],
                idleIDs: [lean, wipe], inSequence: false, doOnce: false, timer: 20,
                claimedBy: actor
            )],
            idlingActorCount: 1,
            report: IdleReport(
                actor: actor, source: "InnLeanMarker",
                trace: [
                    IdleCandidateTrace(
                        id: wipe,
                        editorID: "Pray",
                        depth: 0,
                        verdict: .rejected("GetIsID")
                    ),
                    IdleCandidateTrace(id: lean, editorID: "Lean", depth: 0, verdict: .chosen)
                ],
                chosen: "Lean", plan: nil, seconds: 4, failure: nil
            )
        )
        providers.idleState.head = HeadAssemblySnapshot(
            actor: actor,
            head: ActorHeadReadout(
                source: .baked,
                parts: HeadPartSet(parts: [ResolvedHeadPart(
                    formID: FormID(0x30), editorID: "HairMaleNord01", partType: .hair,
                    origin: .npcOverride, modelPath: "hair.nif", diffuseTexture: nil,
                    normalTexture: nil, tint: SIMD3(0.2, 0.1, 0.05)
                )], misses: []),
                hasBakedHead: true,
                loadedPartCount: 0
            ),
            requested: .baked
        )
        return providers
    }
}
