// The install census and the whole-game estimate, over synthetic files and
// hand-built measurements.

import FormatsMeshTesting
import Foundation
import GameDataTesting
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import Testing

struct AssetProcessingEstimateTests {
    @Test func censusSortsPathsIntoKindsAndRoles() {
        let texture = DDSFixture.rgba8888File(width: 4, height: 4, mipCount: 2)
        let files = InMemoryFileSource(files: [
            "textures\\rock.dds": texture,
            "textures\\rock_n.dds": texture,
            "textures\\rock_s.dds": texture,
            "textures\\broken.dds": Data([1, 2, 3]),
            "textures\\readme.txt": Data(count: 9),
            "meshes\\rock.nif": Data(count: 100),
            "meshes\\actors\\wolf\\animations\\idle.hkx": Data(count: 40),
            "meshes\\actors\\wolf\\skeleton.hkx": Data(count: 40),
            "sound\\fx\\step.wav": Data(count: 30),
            "music\\day.xwm": Data(count: 20)
        ])
        let census = AssetCensus.count(
            files: files, storedSize: { files[$0]?.count }, kinds: Set(AssetKind.allCases)
        )
        let bucket = { (kind: AssetKind, role: TextureRole?) in
            census.buckets.first { $0.kind == kind && $0.role == role }
        }
        // 4x4 plus 2x2 texels per texture.
        #expect(bucket(.texture, .color)?.workUnits == 20)
        #expect(bucket(.texture, .color)?.unreadableCount == 1)
        #expect(bucket(.texture, .normal)?.workUnits == 20)
        #expect(bucket(.texture, .data)?.fileCount == 1)
        #expect(bucket(.mesh, nil)?.workUnits == 100)
        #expect(bucket(.collision, nil)?.workUnits == 100)
        #expect(bucket(.animation, nil)?.fileCount == 1)
        #expect(bucket(.audio, nil)?.workUnits == 50)
    }

    private static func row(
        _ candidate: String,
        readMS: Double = 0,
        convertMS: Double = 0,
        disk: Int = 0
    ) -> AssetCandidateMeasurement {
        AssetCandidateMeasurement(
            candidate: candidate, storage: candidate == "original" ? nil : .raw,
            path: candidate == "original" ? .archive : .cpu,
            timing: AssetLoadTiming(readMS: readMS, decodeMS: 0, uploadMS: 0),
            sizes: (0, disk), fidelity: .lossless, convertMS: convertMS, writeMS: 1
        )
    }

    @Test func estimateScalesTheSampleByWorkUnits() throws {
        let assets = [10, 30].map { units in
            AssetMeasurement(
                entry: AssetSampleEntry(path: "meshes\\a.nif", kind: .mesh),
                detail: "",
                candidates: [
                    Self.row("original", readMS: 2),
                    Self.row("ready", convertMS: 7, disk: units)
                ],
                workUnits: units
            )
        }
        var bucket = AssetCensusBucket(kind: .mesh, role: nil)
        bucket.fileCount = 400
        bucket.workUnits = 400
        let estimates = AssetProcessingEstimate.estimate(
            assets: assets, census: AssetCensus(buckets: [bucket])
        )
        let ready = try #require(estimates.first)
        // Per asset: read 2, convert 7, write 1. The sample is 40 units, the install 400.
        #expect(ready.processingMS == 200)
        #expect(ready.diskBytes == 400)
        #expect(ready.fileCount == 400)
    }
}
