// The settings page switches each lit-mesh term; the snow sparkle switch turns the
// sparkle term off on its own.

import OpenSkyGameData
import OpenSkyRenderResources
@testable import OpenSkyWorld
import Testing

@MainActor
struct SurfaceShadingTermsTests {
    @Test func eachSwitchedOnSettingAddsItsTerm() {
        let store = PlayerSettingsStore(persistence: nil)
        for setting in SurfaceShadingSetting.allCases {
            store.set(setting.id, to: setting == .specular ? 0 : 1)
        }
        store.set(.snowSparkles, to: 1)
        let terms = store.surfaceShadingTerms
        #expect(terms.contains(.normalMaps))
        #expect(terms.contains(.sparkle))
        #expect(!terms.contains(.specular))
    }

    @Test func theSnowSparkleSwitchRemovesTheSparkleTerm() {
        let store = PlayerSettingsStore(persistence: nil)
        for setting in SurfaceShadingSetting.allCases {
            store.set(setting.id, to: 1)
        }
        store.set(.snowSparkles, to: 0)
        #expect(!store.surfaceShadingTerms.contains(.sparkle))
    }
}
