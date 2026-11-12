// Synthetic TRI parser tests. Fixtures are authored bytes, never extracted
// game content (AGENTS.md legal boundary).

import Foundation
@testable import OpenSkyFormatsMesh
import OpenSkyFormatsTesting
import OpenSkyTagsTesting
import simd
import Testing

@Suite(.tags(.parser))
struct TRIFileTests {
    @Test func decodesBaseTopologyAndNamedScaledMorphs() throws {
        let file = try TRIFile(data: TRIFixture.file())

        #expect(file.baseVertices == [
            SIMD3(0, 0, 0), SIMD3(1, 0, 0), SIMD3(0, 1, 0)
        ])
        #expect(file.triangles == [TRITriangle(vertices: SIMD3(0, 1, 2))])
        #expect(file.morphTargets.map(\.name) == ["Aah", "Blink"])
        #expect(file.target(named: "Aah")?.scale == 0.5)
        #expect(file.target(named: "Aah")?.scaledDeltas == [
            SIMD3(0.5, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, -1.5)
        ])
    }

    @Test func rejectsWrongSignatureAndVersion() {
        var signature = TRIFixture.file()
        signature[0] = 0
        #expect(throws: TRIError.malformed("signature is not FRTRI")) {
            _ = try TRIFile(data: signature)
        }

        var version = TRIFixture.file()
        version.replaceSubrange(5 ..< 8, with: Data("004".utf8))
        #expect(throws: TRIError.unsupportedVersion("004")) {
            _ = try TRIFile(data: version)
        }
    }

    @Test func rejectsNegativeCountsAndOutOfRangeFaces() {
        var negative = TRIFixture.file()
        negative.replaceSubrange(8 ..< 12, with: Self.bytes(of: UInt32.max))
        #expect(throws: TRIError.self) { _ = try TRIFile(data: negative) }

        var badFace = TRIFixture.file()
        // Header (64) + three positions (36): first triangle index.
        badFace.replaceSubrange(100 ..< 104, with: Self.bytes(of: UInt32(3)))
        #expect(throws: TRIError.self) { _ = try TRIFile(data: badFace) }
    }

    @Test func rejectsTruncationAndNonTerminatedMorphNames() {
        #expect(throws: TRIError.self) {
            _ = try TRIFile(data: Data(TRIFixture.file().dropLast()))
        }
        var name = TRIFixture.file()
        // Header 64 + vertices 36 + face 12 + UVs 24 + UV face 12 = 148;
        // UInt32 length then "Aah\0".
        name[155] = 0x21
        #expect(throws: TRIError.self) { _ = try TRIFile(data: name) }
    }

    private static func bytes(of value: some FixedWidthInteger) -> Data {
        var little = value.littleEndian
        return withUnsafeBytes(of: &little) { unsafe Data($0) }
    }
}
