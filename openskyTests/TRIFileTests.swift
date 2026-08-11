// Synthetic TRI parser tests. Fixtures are authored bytes, never extracted
// game content (AGENTS.md legal boundary).

import Foundation
@testable import opensky
import simd
import Testing

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
        return withUnsafeBytes(of: &little) { Data($0) }
    }
}

private enum TRIFixture {
    static func file() -> Data {
        var data = Data("FRTRI003".utf8)
        [3, 1, 0, 0, 0, 3, 1, 2, 0, 0, 0, 0, 0, 0]
            .forEach { data.appendInt32($0) }
        [
            SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)
        ].forEach { vertex in
            data.appendFloat32(vertex.x)
            data.appendFloat32(vertex.y)
            data.appendFloat32(vertex.z)
        }
        [0, 1, 2].forEach { data.appendInt32($0) }
        for uv in [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1)] {
            data.appendFloat32(uv.x)
            data.appendFloat32(uv.y)
        }
        [0, 1, 2].forEach { data.appendInt32($0) }
        data.appendMorph(
            name: "Aah", scale: 0.5,
            deltas: [SIMD3(1, 0, 0), SIMD3(0, 2, 0), SIMD3(0, 0, -3)]
        )
        data.appendMorph(
            name: "Blink", scale: 0.25,
            deltas: [SIMD3(0, 0, 0), SIMD3(0, 0, 0), SIMD3(0, 4, 0)]
        )
        return data
    }
}

extension Data {
    fileprivate mutating func appendInt32(_ value: Int) {
        appendUInt32(UInt32(bitPattern: Int32(value)))
    }

    private mutating func appendInt16(_ value: Int16) {
        appendUInt16(UInt16(bitPattern: value))
    }

    fileprivate mutating func appendMorph(
        name: String,
        scale: Float,
        deltas: [SIMD3<Int16>]
    ) {
        let encoded = Data(name.utf8) + Data([0])
        appendUInt32(UInt32(encoded.count))
        append(encoded)
        appendFloat32(scale)
        for delta in deltas {
            appendInt16(delta.x)
            appendInt16(delta.y)
            appendInt16(delta.z)
        }
    }
}
