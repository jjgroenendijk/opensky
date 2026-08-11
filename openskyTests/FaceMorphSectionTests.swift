import AppKit
@testable import opensky
import Testing

@MainActor
struct FaceMorphSectionTests {
    private func makePanel(_ provider: FakeWorldProviders) -> HUDInteractionPanelViewController {
        let panel = HUDInteractionPanelViewController()
        panel.provider = provider
        panel.faceMorphProvider = provider
        panel.loadViewIfNeeded()
        return panel
    }

    @Test
    func controlsExposeStableIdentifiersAndReachProvider() {
        let provider = FakeWorldProviders()
        provider.faceMorphSnapshot = FaceMorphControlSnapshot(
            actor: FormID(0x14),
            targetNames: ["Aah", "BigAah"],
            weights: [:],
            pairedPaths: ["actors/character/character assets/malehead.tri"],
            associationMisses: [],
            unknownTargetCount: 0
        )
        let section = makePanel(provider).faceMorphSection

        #expect(section.targetControl.accessibilityIdentifier() == "FaceMorphTargetControl")
        #expect(section.weightControl.accessibilityIdentifier() == "MorphWeightControl")
        #expect(section.resetControl.accessibilityIdentifier() == "FaceMorphResetControl")
        #expect(section.sectionIdentifier == "faceMorphs")
        section.targetControl.selectItem(withTitle: "Aah")
        section.weightControl.floatValue = 0.75
        section.weightControl.sendAction(
            section.weightControl.action, to: section.weightControl.target
        )
        #expect(provider.faceMorphSnapshot.weights["Aah"] == 0.75)
        #expect(section.isOverridden)

        section.performResetToDefaults()
        #expect(provider.faceMorphSnapshot.weights.isEmpty)
    }

    @Test
    func sectionIsDiscoverableUnderHUDAndInteraction() {
        let panel = makePanel(FakeWorldProviders())
        #expect(panel.makeSections().contains { $0 === panel.faceMorphSection })
    }
}
