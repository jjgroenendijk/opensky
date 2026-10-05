// Packing blobs back to back and splitting them again.

import Foundation
@testable import OpenSkyRendering
import Testing

struct PackedBlobsTests {
    @Test func roundTripsBlobsAndValues() throws {
        let vectors: [SIMD3<Float>] = [SIMD3(1, 2, 3), SIMD3(-4, 5, 0.5)]
        let indices: [UInt32] = [0, 1, 2]
        let packed = PackedBlobs([PackedBlobs.blob(vectors), Data(), PackedBlobs.blob(indices)])
        #expect(packed.ranges.map(\.offset) == [0, 32, 32])
        let blobs = try packed.blobs(from: packed.bytes)
        #expect(PackedBlobs.values(blobs[0], as: SIMD3<Float>.self) == vectors)
        #expect(blobs[1].isEmpty)
        #expect(PackedBlobs.values(blobs[2], as: UInt32.self) == indices)
    }

    @Test func shortSourceThrows() {
        let packed = PackedBlobs([Data([1, 2, 3])])
        #expect(throws: PackedBlobsError.sourceTooShort(expected: 3, actual: 2)) {
            try packed.blobs(from: Data([1, 2]))
        }
    }
}
