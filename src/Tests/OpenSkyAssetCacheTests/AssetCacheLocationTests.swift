// Which folders the cache may use, and the warnings before a build.

import Foundation
@testable import OpenSkyAssetCache
import Testing

struct AssetCacheLocationTests {
    private let base = FileManager.default.temporaryDirectory
        .appending(
            path: "AssetCacheLocationTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

    @Test func aFolderInsideTheGameInstallIsRefused() {
        let install = base.appending(path: "Skyrim Special Edition")
        #expect(throws: AssetCacheLocationError.insideGameInstall) {
            try AssetCacheLocation.validate(
                install.appending(path: "Data/Cache"),
                gameInstall: install
            )
        }
    }

    @Test func aFolderAroundTheGameInstallIsRefused() {
        let install = base.appending(path: "steam/Skyrim Special Edition")
        #expect(throws: AssetCacheLocationError.containsGameInstall) {
            try AssetCacheLocation.validate(base.appending(path: "steam"), gameInstall: install)
        }
    }

    @Test func aFolderInsideAGitCheckoutIsRefused() throws {
        let checkout = base.appending(path: "checkout", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: checkout.appending(path: ".git"),
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: base) }
        #expect(throws: AssetCacheLocationError.self) {
            try AssetCacheLocation.validate(checkout.appending(path: "cache"), gameInstall: nil)
        }
    }

    @Test func aSeparateFolderIsAccepted() throws {
        try AssetCacheLocation.validate(
            base.appending(path: "cache"),
            gameInstall: base.appending(path: "Skyrim Special Edition")
        )
    }

    @Test func theDefaultFolderIsUnderTheUserCaches() throws {
        #expect(try AssetCacheLocation.defaultFolder().path()
            .contains("/Library/Caches/OpenSky/AssetCache"))
    }

    @Test func anInternalDiskWithRoomHasNoWarnings() {
        let volume = AssetCacheVolume(isInternal: true, isLocal: true, availableBytes: 100)
        #expect(AssetCacheLocation.warnings(volume: volume, neededBytes: 50).isEmpty)
    }

    @Test func externalNetworkAndFullDisksWarn() {
        let external = AssetCacheVolume(isInternal: false, isLocal: true, availableBytes: 100)
        #expect(AssetCacheLocation.warnings(volume: external, neededBytes: 50) == [.externalDisk])
        let network = AssetCacheVolume(isInternal: false, isLocal: false, availableBytes: 10)
        #expect(AssetCacheLocation.warnings(volume: network, neededBytes: 50) == [
            .networkDisk, .lowFreeSpace(availableBytes: 10, neededBytes: 50)
        ])
    }

    @Test func theTemporaryFolderHasVolumeFacts() {
        #expect(AssetCacheVolume.of(base.appending(path: "not/yet/made")) != nil)
    }
}
