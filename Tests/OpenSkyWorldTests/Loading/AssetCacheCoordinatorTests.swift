// The Asset Cache page's logic over an in-memory install: settings, check,
// build, a preset change, clear, and a refused folder.

import EngineTesting
import Foundation
import OpenSkyAssetCache
import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

/// Stores each `.hkx` file as it is.
private struct CopyConverter: AssetConverting {
    var kind: AssetCacheKind {
        .collision
    }

    var version: UInt32 {
        1
    }

    func accepts(path: String) -> Bool {
        path.hasSuffix(".hkx")
    }

    func convert(path _: String, bytes: Data, preset _: AssetQualityPreset) throws -> Data? {
        bytes
    }
}

@MainActor
struct AssetCacheCoordinatorTests {
    private let install = FileManager.default.temporaryDirectory
        .appending(
            path: "AssetCacheCoordinatorInstall-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
    private let folder = FileManager.default.temporaryDirectory
        .appending(
            path: "AssetCacheCoordinatorTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )

    private func makeCoordinator() -> AssetCacheCoordinator {
        let files = InMemoryFileSource(files: [
            "meshes\\a.hkx": Data([1, 2]), "meshes\\b.hkx": Data([3]), "meshes\\c.txt": Data([4])
        ])
        let install = install
        return AssetCacheCoordinator(
            store: PlayerSettingsStore(persistence: nil),
            environment: AssetCacheCoordinator.Environment(
                locate: { (files, install) }, makeConverters: { _ in [CopyConverter()] }
            )
        )
    }

    /// Runs `start` and returns when the job it started is done.
    private func run(_ coordinator: AssetCacheCoordinator, _ start: () -> Void) async {
        var sawJob = false
        await withCheckedContinuation { continuation in
            coordinator.onChange = { [weak coordinator] in
                guard coordinator?.activity == .idle else {
                    sawJob = true
                    return
                }
                guard sawJob else { return }
                coordinator?.onChange = nil
                continuation.resume()
            }
            start()
        }
    }

    @Test func aBuildMakesTheCacheCurrentAndAPresetChangeMakesItStale() async {
        let coordinator = makeCoordinator()
        await run(coordinator) { coordinator.setFolder(folder) }
        #expect(coordinator.check?.summary == .notBuilt)
        await run(coordinator) { coordinator.startBuild() }
        #expect(coordinator.progress?.converted == 2)
        #expect(coordinator.check?.summary == .current)
        #expect(coordinator.usage?.entryCount == 2)
        await run(coordinator) { coordinator.setPreset(.highestQuality) }
        #expect(coordinator.check?.summary == .stale)
        await run(coordinator) { coordinator.clear() }
        #expect(coordinator.check == nil)
        #expect(coordinator.usage?.entryCount == 0)
    }

    @Test func aFolderInsideTheInstallIsRefused() async {
        let coordinator = makeCoordinator()
        await run(coordinator) { coordinator.setFolder(install.appending(path: "Cache")) }
        #expect(coordinator
            .problem == "The folder is inside the game folder. Choose another folder.")
        #expect(coordinator.check == nil)
    }

    @Test func settingsAreSavedToTheStore() {
        let store = PlayerSettingsStore(persistence: nil)
        let coordinator = AssetCacheCoordinator(store: store)
        coordinator.setEnabled(false)
        coordinator.setLimitGiB(40)
        #expect(AssetCacheSettings(store: store) == AssetCacheSettings(
            isEnabled: false, preset: .default, folder: nil, limitBytes: 40 << 30
        ))
    }

    @Test func theReadoutNamesTheStateAndTheBuild() {
        var check = AssetCacheCheck()
        check.kinds[.texture] = AssetCacheKindCheck(current: 3, stale: 0, missing: 1)
        #expect(AssetCacheReadout
            .stateLine(check, activity: .idle) == "State: partly built, 3 of 4 files")
        #expect(AssetCacheReadout.stateLine(nil, activity: .checking) == "State: checking")
        var progress = AssetCacheBuildProgress()
        progress.totalFiles = 10
        progress.doneFiles = 4
        progress.converted = 4
        #expect(AssetCacheReadout.buildLine(progress, isBuilding: true) == "Build: 4 of 10 files")
        progress.isCancelled = true
        #expect(AssetCacheReadout
            .buildLine(progress, isBuilding: false) == "Build: cancelled, 4 converted, 0 failed")
        #expect(AssetCacheReadout
            .presetTitle(.balanced, cores: 4) == "Balanced: about 21 GiB, 8 min to build")
        #expect(AssetCacheReadout.sizeLine(
            AssetCacheUsage(entryCount: 2, bytes: 3 << 29),
            limitBytes: 25 << 30
        )
            == "Size: 1.5 GiB of 25 GiB, 2 entries")
    }
}
