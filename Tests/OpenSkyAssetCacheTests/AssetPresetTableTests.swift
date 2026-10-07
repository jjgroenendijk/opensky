// The quality preset table and the cache settings in the shared settings store.

import Foundation
@testable import OpenSkyAssetCache
import OpenSkyGameData
import Testing

private final class MemorySettings: PlayerSettingsPersistence {
    var data: Data?

    func loadSettings() throws -> Data? {
        data
    }

    func saveSettings(_ data: Data) throws {
        self.data = data
    }
}

struct AssetPresetTableTests {
    @Test(arguments: [
        ("textures\\rock01.dds", AssetTextureClass.color),
        ("textures\\rock01_n.dds", .normal),
        ("textures\\actors\\body_msn.dds", .normal),
        ("textures\\armor\\iron_s.dds", .data),
        ("textures\\effects\\glow_g.dds", .data),
        ("textures\\architecture\\wall_m.dds", .data)
    ])
    func texturesAreGroupedByTheirSuffix(path: String, expected: AssetTextureClass) {
        #expect(AssetTextureClass(path: path) == expected)
    }

    @Test(arguments: [
        ("sound\\fx\\wpn\\swing\\a.wav", AssetSoundCategory.effects),
        ("sound\\fx\\voc\\shout\\a.wav", .voice),
        ("sound\\voice\\skyrim.esm\\a.fuz", .voice),
        ("sound\\fx\\ambr\\birds\\a.wav", .ambience),
        ("sound\\fx\\amb\\wind\\a.wav", .ambience),
        ("music\\stinger\\a.xwm", .music)
    ])
    func soundsAreGroupedByTheirFolder(path: String, expected: AssetSoundCategory) {
        #expect(AssetSoundCategory(path: path) == expected)
    }

    @Test(arguments: AssetQualityPreset.allCases)
    func noSoundCategoryPassedTheAACCheck(preset: AssetQualityPreset) {
        let values = preset.values
        #expect(AssetSoundCategory.allCases
            .allSatisfy { values.audio[$0, default: .alac] == .alac })
        #expect(values.audioStorage(forPath: "sound\\fx\\a.wav") == .alac)
    }

    @Test func highestQualityKeepsEveryShippedTextureLossless() {
        let values = AssetQualityPreset.highestQuality.values
        #expect(AssetTextureClass.allCases.allSatisfy { values.textures[$0] == .shipped })
        #expect(values.imageLimit == .lossless)
    }

    @Test func balancedOnlyCompressesNormalMaps() {
        let values = AssetQualityPreset.balanced.values
        #expect(values.textureStorage(forPath: "a_n.dds") == .astc4x4)
        #expect(values.textureStorage(forPath: "a.dds") == .shipped)
        #expect(values.textureStorage(forPath: "a_s.dds") == .shipped)
        #expect(values.imageLimit == AssetImageLimit(minimumPSNR: 40, maximumNormalDegrees: 2))
    }

    @Test func bestPerformanceUsesASTCEverywhereAndStaysAboveThirtyDecibels() {
        let values = AssetQualityPreset.bestPerformance.values
        #expect(values.textureStorage(forPath: "a.dds") == .astc6x6)
        #expect(values.textureStorage(forPath: "a_n.dds") == .astc6x6)
        #expect(values.textureStorage(forPath: "a_g.dds") == .astc8x8)
        #expect(values.imageLimit.minimumPSNR == 30)
    }

    @Test func aFasterPresetBuildsLonger() {
        let times = AssetQualityPreset.allCases.map { $0.estimatedBuildSeconds(cores: 8) }
        #expect(times == times.sorted(by: >))
        #expect(AssetQualityPreset.highestQuality.estimatedBuildSeconds(cores: 2) == 450)
    }

    @MainActor
    @Test func theSettingsSurviveARestartThroughTheSharedStore() {
        let disk = MemorySettings()
        let store = PlayerSettingsStore(persistence: disk)
        #expect(AssetCacheSettings(store: store) == AssetCacheSettings())
        let chosen = AssetCacheSettings(
            isEnabled: false, preset: .bestPerformance, folder: URL(
                filePath: "/Volumes/Fast/Cache/",
                directoryHint: .isDirectory
            ),
            limitBytes: 40 << 30
        )
        chosen.save(to: store)
        let reloaded = AssetCacheSettings(store: PlayerSettingsStore(persistence: disk))
        #expect(reloaded.isEnabled == false)
        #expect(reloaded.preset == .bestPerformance)
        #expect(reloaded.folder?.path(percentEncoded: false) == "/Volumes/Fast/Cache/")
        #expect(reloaded.effectiveLimitBytes == 40 << 30)
    }
}
