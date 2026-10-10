// The Asset Optimisation page's logic over an in-memory install: settings, check,
// conversion, a quality change, clear, and a refused folder.

import Foundation
import OpenSkyAssetCache
import OpenSkyEngineTesting
import OpenSkyGameData
import OpenSkyRendering
@testable import OpenSkyWorld
import Testing

/// Stores each file with `suffix` as it is.
private struct CopyConverter: AssetConverting {
    let kind: AssetCacheKind
    let suffix: String

    var version: UInt32 {
        1
    }

    func accepts(path: String) -> Bool {
        path.hasSuffix(suffix)
    }

    func convert(path _: String, bytes: Data, output _: AssetTextureOutput) throws -> Data? {
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
            "meshes\\a.hkx": Data([1, 2]), "meshes\\b.hkx": Data([3]), "meshes\\c.txt": Data([4]),
            "textures\\d.dds": Data([5, 6])
        ])
        let converters: [any AssetConverting] = [
            CopyConverter(kind: .collision, suffix: ".hkx"), CopyConverter(
                kind: .texture,
                suffix: ".dds"
            )
        ]
        let install = install
        return AssetCacheCoordinator(
            store: PlayerSettingsStore(persistence: nil),
            environment: AssetCacheCoordinator.Environment(
                locate: { (files, install) }, makeConverters: { _ in converters }
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

    @Test func aConversionMakesEveryFileCurrentAndAQualityChangeOnlyTheTexturesStale() async {
        let coordinator = makeCoordinator()
        await run(coordinator) { coordinator.setFolder(folder) }
        #expect(coordinator.check?.summary == .notBuilt)
        #expect(coordinator.status.needsConversion)
        await run(coordinator) { coordinator.startBuild() }
        #expect(coordinator.progress?.converted == 3)
        #expect(coordinator.check?.summary == .current)
        #expect(coordinator.status == .ready)
        #expect(coordinator.convertDisabledReason == "Every file is optimised")
        await run(coordinator) { coordinator.setTextureQuality(.low) }
        #expect(coordinator.check?.kinds[.texture]?.stale == 1)
        #expect(coordinator.check?.kinds[.collision]?.stale == 0)
        #expect(coordinator.convertDisabledReason == nil)
        await run(coordinator) { coordinator.clear() }
        #expect(coordinator.check?.summary == .notBuilt)
        #expect(coordinator.usage?.entryCount == 0)
    }

    @Test func convertIsOffWhileOptimisationIsOff() {
        let coordinator = AssetCacheCoordinator(store: PlayerSettingsStore(persistence: nil))
        coordinator.setEnabled(false)
        #expect(coordinator.convertDisabledReason == "Turn on asset optimisation first")
    }

    @Test func aKindTurnedOffIsNotBuiltOrCounted() async {
        let coordinator = makeCoordinator()
        await run(coordinator) { coordinator.setFolder(folder) }
        await run(coordinator) { coordinator.setKind(.collision, stored: false) }
        #expect(coordinator.check?.kinds[.collision] == nil)
        #expect(coordinator.check?.total.total == 1)
        await run(coordinator) { coordinator.startBuild() }
        #expect(coordinator.progress?.converted == 1)
        #expect((coordinator.usage?.kinds[.collision]?.entryCount ?? 0) == 0)
        await run(coordinator) { coordinator.setKind(.collision, stored: true) }
        await run(coordinator) { coordinator.startBuild() }
        #expect(coordinator.usage?.kinds[.collision]?.entryCount == 2)
        #expect(AssetCacheReadout.kindTitle(.collision, usage: coordinator.usage)
            .hasPrefix("Collision: 2 entries, "))
        #expect(AssetCacheReadout.kindGain(.audio) == "Measured: no faster than the archives")
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
        coordinator.setTextureQuality(.low)
        coordinator.setTextureFormat(.astc6x6, for: .normal)
        coordinator.setDirectLoad(DirectGPULoading(meshes: true))
        #expect(AssetCacheSettings(store: store) == AssetCacheSettings(
            isEnabled: false,
            textureOutput: AssetTextureOutput(quality: .low, formats: [.normal: .astc6x6]),
            directLoad: DirectGPULoading(meshes: true)
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
        #expect(AssetCacheReadout
            .buildLine(progress, isBuilding: true) == "Conversion: 4 of 10 files")
        progress.isCancelled = true
        #expect(AssetCacheReadout
            .buildLine(progress, isBuilding: false) ==
            "Conversion: cancelled, 4 converted, 0 failed")
        #expect(AssetCacheReadout.qualityTitle(.high) == "High: no visible loss")
        #expect(AssetCacheReadout.sizeLine(AssetCacheUsage(entryCount: 2, bytes: 3 << 29))
            == "Size: 1.5 GiB, 2 files")
        #expect(AssetCacheReadout.sizeLine(nil) == "Size: empty")
    }

    @Test func directLoadingSaysWhyItIsInactive() {
        var settings = AssetCacheSettings()
        let ready = AssetOptimisationStatus.ready
        let external = AssetCacheVolume(isInternal: false, isLocal: true, availableBytes: 1 << 40)
        #expect(AssetOptimisationReadout.directLoadStatus(settings, volume: nil, status: ready)
            == "Active: textures load straight into GPU memory")
        #expect(AssetOptimisationReadout.directLoadStatus(settings, volume: external, status: ready)
            == "Inactive: the folder is on an external disk")
        #expect(AssetOptimisationReadout.directLoadStatus(
            settings, volume: nil, status: .notConverted(waiting: "")
        ) == "Inactive: no optimised files yet")
        settings.isEnabled = false
        #expect(AssetOptimisationReadout.directLoadStatus(settings, volume: nil, status: ready)
            == "Inactive: asset optimisation is off")
        settings.directLoad.isEnabled = false
        #expect(AssetOptimisationReadout.directLoadStatus(settings, volume: nil, status: ready)
            == "Off: optimised files load through the CPU")
    }

    @Test func aWaitingTextureChangeNamesItsCount() {
        var check = AssetCacheCheck()
        #expect(AssetOptimisationReadout
            .textureChangeLine(check, output: AssetTextureOutput()) == nil)
        check.kinds[.texture] = AssetCacheKindCheck(
            current: 0,
            stale: 2,
            missing: 0,
            pendingSourceBytes: 1000
        )
        let line = AssetOptimisationReadout.textureChangeLine(check, output: AssetTextureOutput())
        #expect(line?.hasPrefix("Needs a new conversion: 2 textures, about ") == true)
        #expect(AssetOptimisationReadout
            .qualityLimitLine(.original) == "Original: the shipped blocks, unchanged")
    }

    @Test func texturesFromAnExternalDiskShowAsCPULoads() {
        var stats = FastTextureLoadStats()
        #expect(AssetCacheReadout
            .directLoadLines(stats) == ["Direct GPU loading: no cell loaded yet"])
        stats.externalSkips = 12
        #expect(AssetCacheReadout.directLoadLines(stats)
            .last == "External disk: 12 loaded on the CPU")
    }
}
