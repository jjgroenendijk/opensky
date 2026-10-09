// The Asset Optimisation status and the space check, from counted checks.

import Foundation
import OpenSkyAssetCache
import Testing

struct AssetOptimisationStatusTests {
    private func check(
        _ textures: AssetCacheKindCheck,
        meshes: AssetCacheKindCheck = .init()
    ) -> AssetCacheCheck {
        var check = AssetCacheCheck()
        check.kinds[.texture] = textures
        check.kinds[.mesh] = meshes
        return check
    }

    @Test func eachStateFollowsTheCheck() {
        let none = check(.init(missing: 41210), meshes: .init(missing: 3))
        #expect(AssetOptimisationStatus(check: none, isChecking: false, conversion: nil)
            == .notConverted(waiting: "Waiting: base game \(41210.formatted()) textures, 3 meshes"))
        let part = check(.init(current: 5, missing: 1))
        #expect(AssetOptimisationStatus(check: part, isChecking: false, conversion: nil)
            == .needsConversion(waiting: "Waiting: base game 1 texture"))
        let stale = check(.init(current: 5, stale: 2))
        #expect(AssetOptimisationStatus(check: stale, isChecking: false, conversion: nil)
            .needsConversion)
        let done = check(.init(current: 5))
        #expect(AssetOptimisationStatus(check: done, isChecking: false, conversion: nil) == .ready)
    }

    @Test func checkingAndConvertingWinOverTheLastCheck() {
        let done = check(.init(current: 5))
        #expect(AssetOptimisationStatus(check: done, isChecking: true, conversion: nil) ==
            .checking)
        #expect(AssetOptimisationStatus(check: nil, isChecking: false, conversion: nil) ==
            .checking)
        #expect(AssetOptimisationStatus(check: done, isChecking: false, conversion: "1 of 2")
            == .converting(progress: "1 of 2"))
    }

    @Test func everyStateHasASymbolAndWords() {
        let states: [AssetOptimisationStatus] = [
            .checking, .ready, .needsConversion(waiting: "a"), .notConverted(waiting: "b"),
            .converting(progress: "c")
        ]
        #expect(Set(states.map(\.symbolName)).count == states.count)
        #expect(states.allSatisfy { !$0.title.isEmpty && !$0.detail.isEmpty })
    }

    @Test func theSpaceCheckScalesWaitingBytesByTheMeasuredRatio() {
        let waiting = check(
            .init(missing: 1, pendingSourceBytes: 1000),
            meshes: .init(missing: 1, pendingSourceBytes: 100)
        )
        let volume = AssetCacheVolume(isInternal: true, isLocal: true, availableBytes: 10000)
        let original = AssetSpaceCheck(check: waiting, output: AssetTextureOutput(), volume: volume)
        let low = AssetSpaceCheck(
            check: waiting,
            output: AssetTextureOutput(quality: .low),
            volume: volume
        )
        #expect(original.neededBytes == UInt64(1000 * AssetOutputRatio.ratio(
            .texture,
            output: AssetTextureOutput()
        )
            + 100 * AssetOutputRatio.ratio(.mesh, output: AssetTextureOutput())))
        #expect(low.neededBytes < original.neededBytes)
        #expect(original.fits)
        #expect(original.warnings.isEmpty)
    }

    @Test func aConversionThatDoesNotFitIsRefusedAndAnExternalDiskWarned() {
        let waiting = check(.init(missing: 1, pendingSourceBytes: 1 << 30))
        let small = AssetCacheVolume(isInternal: false, isLocal: true, availableBytes: 1 << 20)
        let space = AssetSpaceCheck(check: waiting, output: AssetTextureOutput(), volume: small)
        #expect(!space.fits)
        #expect(space.warnings.contains(.externalDisk))
        #expect(space.warnings.contains {
            if case .lowFreeSpace = $0 {
                true
            } else {
                false
            }
        })
        #expect(space.line.hasPrefix("Space: needs "))
    }

    @Test func anUnreadVolumeNeverBlocks() {
        let space = AssetSpaceCheck(neededBytes: 1 << 40, volume: nil)
        #expect(space.fits)
        #expect(space.line.hasSuffix("free space unknown"))
    }
}
