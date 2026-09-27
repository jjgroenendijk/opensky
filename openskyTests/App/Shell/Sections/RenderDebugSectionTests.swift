// World > Render Debug verification surface (issue #144): the section reached
// through the real registry factory, its accessibility ids, and the round trip
// from a control back into the provider and out again as a readout.
//
// The ids asserted here are the UI-test API; changing one is a deliberate act
// that updates these literals in the same commit (docs/tools/app-ui.md).

import AppKit
@testable import opensky
import Testing

@MainActor
struct RenderDebugSectionTests {
    private func makePanel(_ providers: FakeWorldProviders) throws -> WorldPanelViewController {
        let descriptor = try #require(DestinationRegistry.all.first { $0.id == "world" })
        guard case let .worldInspector(makePanel) = descriptor.content else {
            Issue.record("World is not a world inspector")
            throw RenderDebugSectionTestError.notAWorldInspector
        }
        let panel = try #require(
            makePanel(WorldPanelContext(providers: providers)) as? WorldPanelViewController
        )
        panel.loadViewIfNeeded()
        return panel
    }

    @Test
    func theSectionIsReachableUnderTheWorldDestination() throws {
        let panel = try makePanel(FakeWorldProviders())
        let ids = panel.sections.map(\.sectionIdentifier)
        #expect(ids.contains("renderDebug"))
    }

    @Test
    func everyControlCarriesItsPinnedIdentifier() throws {
        let panel = try makePanel(FakeWorldProviders())
        var found: Set<String> = []
        Self.collectIdentifiers(in: panel.view, into: &found)
        let expected: Set = [
            "RenderDebugModeControl", "RenderDebugSoloControl", "RenderDebugStatsLabel",
            "RenderDebugLayerStaticsControl", "RenderDebugLayerActorsControl",
            "RenderDebugLayerDistantLODControl", "RenderDebugLayerTerrainControl",
            "RenderDebugLayerGrassControl", "RenderDebugLayerWaterControl",
            "RenderDebugLayerSkyControl", "RenderDebugLayerParticlesControl"
        ]
        #expect(expected.isSubset(of: found), "missing: \(expected.subtracting(found))")
    }

    @Test
    func choosingAChannelReachesTheProviderAndTheReadout() throws {
        let providers = FakeWorldProviders()
        let panel = try makePanel(providers)
        let control = panel.renderDebugModeControl
        let index = try #require(RenderDebugMode.allCases.firstIndex(of: .worldNormals))
        control.selectItem(at: index)
        control.sendAction(control.action, to: control.target)

        #expect(providers.renderDebugMode == .worldNormals)
        #expect(
            scriptsReadout("RenderDebugStatsLabel", in: panel.view)?
                .contains("View: World normals") == true
        )
    }

    @Test
    func isolatingALayerLeavesTheCheckboxesAgreeingWithTheMask() throws {
        let providers = FakeWorldProviders()
        let panel = try makePanel(providers)
        let solo = panel.renderDebugSoloControl
        // Item 0 is "no isolation"; the rest follow `RenderLayer.ordered`.
        let index = try #require(RenderLayer.ordered.firstIndex(of: .terrain))
        solo.selectItem(at: index + 1)
        solo.sendAction(solo.action, to: solo.target)

        #expect(providers.renderDebugLayers == .terrain)
        let terrain = try #require(
            Self.control("RenderDebugLayerTerrainControl", in: panel.view) as? NSButton
        )
        let grass = try #require(
            Self.control("RenderDebugLayerGrassControl", in: panel.view) as? NSButton
        )
        #expect(terrain.state == .on)
        #expect(grass.state == .off)
        #expect(
            scriptsReadout("RenderDebugStatsLabel", in: panel.view)?
                .contains("solo Terrain") == true
        )
    }

    @Test
    func unpickingALayerCheckboxRemovesOnlyThatLayer() throws {
        let providers = FakeWorldProviders()
        let panel = try makePanel(providers)
        let water = try #require(
            Self.control("RenderDebugLayerWaterControl", in: panel.view) as? NSButton
        )
        water.state = .off
        water.sendAction(water.action, to: water.target)

        #expect(!providers.renderDebugLayers.contains(.water))
        #expect(providers.renderDebugLayers.contains(.terrain))
    }

    @Test
    func aDebugViewOrAHiddenLayerLightsTheDestinationDot() throws {
        let providers = FakeWorldProviders()
        let descriptor = try #require(DestinationRegistry.all.first { $0.id == "world" })
        let overrides = try #require(descriptor.overrides)
        let context = WorldPanelContext(providers: providers)
        #expect(!overrides.isOverridden(context))

        providers.renderDebugMode = .mipLevel
        #expect(overrides.isOverridden(context))
        overrides.resetToDefaults(context)
        #expect(providers.renderDebugMode == .off)

        providers.renderDebugLayers = .statics
        #expect(overrides.isOverridden(context))
        overrides.resetToDefaults(context)
        #expect(providers.renderDebugLayers == .all)
    }

    // MARK: - Helpers

    private static func collectIdentifiers(in view: NSView, into found: inout Set<String>) {
        let identifier = view.accessibilityIdentifier()
        if !identifier.isEmpty {
            found.insert(identifier)
        }
        for subview in view.subviews {
            collectIdentifiers(in: subview, into: &found)
        }
    }

    private static func control(_ identifier: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == identifier {
            return view
        }
        for subview in view.subviews {
            if let found = control(identifier, in: subview) {
                return found
            }
        }
        return nil
    }
}

enum RenderDebugSectionTestError: Error {
    case notAWorldInspector
}
