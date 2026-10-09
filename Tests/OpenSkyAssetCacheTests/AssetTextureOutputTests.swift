// The texture output rules and the optimisation settings in the shared settings store.

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

struct AssetTextureOutputTests {
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

    @Test func originalKeepsEveryTextureShipped() {
        let output = AssetTextureOutput(quality: .original)
        #expect(output.plan(forPath: "a.dds") == .shipped)
        #expect(output.plan(forPath: "a_n.dds") == .shipped)
        #expect(output.variant(forPath: "a.dds") == 0)
        #expect(!output.needsEncoder)
    }

    @Test func aQualitySearchesAndAForcedFormatWinsForItsGroup() throws {
        let output = AssetTextureOutput(
            quality: .medium,
            formats: [.normal: .astc4x4, .data: .shipped]
        )
        let target = try #require(TextureQuality.medium.target)
        #expect(output.plan(forPath: "a.dds") == .search(target))
        #expect(output.plan(forPath: "a_n.dds") == .forced(.astc4x4))
        #expect(output.plan(forPath: "a_s.dds") == .shipped)
        #expect(output.needsEncoder)
    }

    @Test func eachOutputHasItsOwnVariantByte() {
        let quality = AssetTextureOutput(quality: .high)
        let forced = AssetTextureOutput(formats: [.color: .astc6x6])
        let limited = AssetTextureOutput(maximumSide: 1024)
        let bytes = [
            AssetTextureOutput().variant(forPath: "a.dds"), quality.variant(forPath: "a.dds"),
            forced.variant(forPath: "a.dds"), limited.variant(forPath: "a.dds")
        ]
        #expect(Set(bytes).count == bytes.count)
        #expect(limited.variant(forPath: "a.dds") >> 5 == 3)
    }

    @Test func theSearchNeverTriesAFormatLargerThanShipped() {
        #expect(TextureFormatSearch.candidates(shipped: .bc1, width: 1024, height: 1024)
            == [.astc8x8, .astc6x6])
        #expect(TextureFormatSearch.candidates(shipped: .bc7, width: 1024, height: 1024)
            == [.astc8x8, .astc6x6, .astc5x5])
        #expect(TextureFormatSearch.candidates(shipped: .bc7, width: 256, height: 128).isEmpty)
    }

    @Test func thePickIsTheFirstFormatThatMeetsTheTarget() throws {
        let target = try #require(TextureQuality.high.target)
        var tried: [ReadyTextureFormat] = []
        let pick = TextureFormatSearch.pick(
            TextureFormatSearch.order, target: target, normalMap: false, cutoutAlpha: false
        ) { format in
            tried.append(format)
            let psnr = format == .astc5x5 ? 45.0 : 30
            return TextureMeasure(rgbPSNR: psnr, alphaPSNR: 100, normalDegrees: nil)
        }
        #expect(pick == .astc5x5)
        #expect(tried == [.astc8x8, .astc6x6, .astc5x5])
    }

    @Test func cutOutAlphaAndNormalsUseTheirOwnLimits() throws {
        let target = try #require(TextureQuality.medium.target)
        let measure = TextureMeasure(rgbPSNR: 40, alphaPSNR: 40, normalDegrees: 3)
        #expect(target.isMet(by: measure, normalMap: false, cutoutAlpha: false))
        #expect(!target.isMet(by: measure, normalMap: false, cutoutAlpha: true))
        #expect(target.isMet(by: measure, normalMap: true, cutoutAlpha: false))
        let bent = TextureMeasure(rgbPSNR: 40, alphaPSNR: 40, normalDegrees: 5)
        #expect(!target.isMet(by: bent, normalMap: true, cutoutAlpha: false))
    }

    @Test func noFormatMeetingTheTargetKeepsTheShippedBlocks() throws {
        let target = try #require(TextureQuality.high.target)
        let pick = TextureFormatSearch.pick(
            TextureFormatSearch.order, target: target, normalMap: false, cutoutAlpha: false
        ) { _ in TextureMeasure(rgbPSNR: 20, alphaPSNR: 20, normalDegrees: nil) }
        #expect(pick == nil)
    }

    @MainActor
    @Test func theSettingsSurviveARestartThroughTheSharedStore() {
        let disk = MemorySettings()
        let store = PlayerSettingsStore(persistence: disk)
        #expect(AssetCacheSettings(store: store) == AssetCacheSettings())
        let chosen = AssetCacheSettings(
            isEnabled: false,
            textureOutput: AssetTextureOutput(quality: .low, formats: [.normal: .astc4x4]),
            folder: URL(filePath: "/Volumes/Fast/Cache/", directoryHint: .isDirectory),
            directLoad: DirectGPULoading(meshes: true, allDisks: true),
            kinds: [.texture, .mesh]
        )
        chosen.save(to: store)
        let reloaded = AssetCacheSettings(store: PlayerSettingsStore(persistence: disk))
        #expect(reloaded.isEnabled == false)
        #expect(reloaded.textureOutput == chosen.textureOutput)
        #expect(reloaded.directLoad == chosen.directLoad)
        #expect(reloaded.folder?.path(percentEncoded: false) == "/Volumes/Fast/Cache/")
        #expect(reloaded.kinds == [.texture, .mesh])
    }

    @Test func everyKindHasASettingsRowThatDefaultsToOn() {
        for kind in AssetCacheKind.built {
            let row = PlayerSettingsCatalog.vanilla
                .definition(.assetKind(folder: kind.folderName))
            #expect(row?.defaultValue == 1)
            #expect(AssetCacheKind(folderName: kind.folderName) == kind)
        }
    }
}
