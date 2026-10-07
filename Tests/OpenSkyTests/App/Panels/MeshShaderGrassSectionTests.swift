// Developer > Rendering Performance > Mesh-Shader Grass: the switch and the meshlet readout.

import AppKit
@testable import OpenSky
@testable import OpenSkyRendering
import Testing

@MainActor
struct MeshShaderGrassSectionTests {
    private static func section(
        _ providers: FakeWorldProviders, status: MeshShaderGrassStatus
    ) -> MeshShaderGrassSection {
        var snapshot = RenderPerformanceSnapshot()
        snapshot.meshShaderGrass = status
        providers.renderPerformanceSnapshot = snapshot
        let section = MeshShaderGrassSection()
        section.provider = providers
        section.loadViewIfNeeded()
        section.refreshReadout()
        return section
    }

    @Test
    func theSwitchReachesTheProviderAndCountsAsAnOverride() {
        let providers = FakeWorldProviders()
        let section = Self.section(providers, status: MeshShaderGrassStatus())
        let control = section.enabledControl
        #expect(control.accessibilityIdentifier() == "MeshShaderGrassControl")
        #expect(control.isEnabled)
        #expect(section.statsReadout == "Grass path: classic")
        control.state = .on
        control.sendAction(control.action, to: section)
        #expect(providers.meshShaderGrassEnabled)
        #expect(MeshShaderGrassSection.isOverridden(provider: providers))
        MeshShaderGrassSection.resetToDefaults(provider: providers)
        #expect(!providers.meshShaderGrassEnabled)
    }

    @Test
    func theReadoutShowsTheMeshletCounts() {
        let providers = FakeWorldProviders()
        providers.meshShaderGrassEnabled = true
        let section = Self.section(providers, status: MeshShaderGrassStatus(
            enabled: true, counts: MeshletCounts(tested: 900, drawn: 600, meshes: 12)
        ))
        #expect(section.statsReadout == """
        Grass path: mesh shader
        Meshes: 12  Meshlets tested: 900
        Drawn: 600  Culled: 300
        """)
    }

    @Test
    func aGPUWithoutMeshShadersDisablesTheSwitch() {
        let providers = FakeWorldProviders()
        providers.meshShaderGrassEnabled = true
        let section = Self.section(providers, status: MeshShaderGrassStatus(
            enabled: true, unavailableReason: "This GPU has no mesh shaders"
        ))
        #expect(!section.enabledControl.isEnabled)
        #expect(section.enabledControl.state == .off)
        #expect(section.statsReadout.hasSuffix("Unavailable: This GPU has no mesh shaders"))
    }
}
