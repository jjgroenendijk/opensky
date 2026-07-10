// NiNode + shared AV-object prefix decode tests over synthetic in-code
// payloads (NIFFixture). Layouts per NifTools nif.xml; docs/formats/nif.md.

import Foundation
@testable import opensky
import simd
import Testing

struct NIFNodeTests {
    private func header(strings: [String] = []) throws -> NIFHeader {
        var reader = BinaryReader(NIFFixture.header(strings: strings))
        return try NIFHeader(reader: &reader)
    }

    @Test func decodesNameFlagsTransformAndChildren() throws {
        let payload = NIFFixture.niNode(
            prefix: NIFFixture.avObjectPrefix(
                nameIndex: 1,
                flags: 0x8000E,
                translation: SIMD3(10, -20, 30),
                rotationColumns: [0, 1, 0, -1, 0, 0, 0, 0, 1],
                scale: 2,
                collisionRef: 7
            ),
            children: [2, -1, 5]
        )
        let node = try NIFNode(
            data: payload,
            header: header(strings: ["Scene Root", "TestNode"])
        )
        #expect(node.object.name == "TestNode")
        #expect(node.object.flags == 0x8000E)
        #expect(node.object.translation == SIMD3(10, -20, 30))
        #expect(node.object.rotation.columns.0 == SIMD3(0, 1, 0))
        #expect(node.object.rotation.columns.1 == SIMD3(-1, 0, 0))
        #expect(node.object.scale == 2)
        #expect(node.object.collisionRef == 7)
        #expect(node.children == [2, -1, 5])
    }

    @Test func unnamedAndJunkNameIndexesResolveToNil() throws {
        let header = try header(strings: ["OnlyString"])
        let unnamed = try NIFNode(
            data: NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(nameIndex: .max)),
            header: header
        )
        #expect(unnamed.object.name == nil)
        // Out-of-range index is lenient: garbage tables must not reject a mesh.
        let junk = try NIFNode(
            data: NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(nameIndex: 99)),
            header: header
        )
        #expect(junk.object.name == nil)
    }

    @Test func skipsExtraDataRefsBeforeTransform() throws {
        let payload = NIFFixture.niNode(
            prefix: NIFFixture.avObjectPrefix(
                extraDataRefs: [3, 4, 9],
                translation: SIMD3(1, 2, 3)
            ),
            children: [6]
        )
        let node = try NIFNode(data: payload, header: header())
        #expect(node.object.translation == SIMD3(1, 2, 3))
        #expect(node.children == [6])
    }

    @Test func localTransformComposesTranslationRotationScale() throws {
        // Rotation columns = MatrixMath.rotationZ(θ) upper 3x3, so the
        // composed local transform must equal T * Rz(θ) * S.
        let theta = MatrixMath.radians(fromDegrees: 30)
        let node = try NIFNode(
            data: NIFFixture.niNode(prefix: NIFFixture.avObjectPrefix(
                translation: SIMD3(5, 6, 7),
                rotationColumns: [
                    cosf(theta), sinf(theta), 0,
                    -sinf(theta), cosf(theta), 0,
                    0, 0, 1
                ],
                scale: 3
            )),
            header: header()
        )
        let expected = MatrixMath.translation(SIMD3(5, 6, 7))
            * MatrixMath.rotationZ(radians: theta)
            * MatrixMath.scale(uniform: 3)
        let got = node.object.localTransform
        for column in 0 ..< 4 {
            #expect(simd_length(got[column] - expected[column]) < 1e-6)
        }
    }

    @Test func oversizedChildCountIsMalformed() throws {
        var payload = NIFFixture.avObjectPrefix()
        payload.appendUInt32(0xFFFF) // children that cannot fit the block
        #expect(throws: NIFError.self) {
            try NIFNode(data: payload, header: header())
        }
    }

    @Test func oversizedExtraDataCountIsMalformed() throws {
        var payload = Data()
        payload.appendUInt32(0xFFFF_FFFF) // name: none
        payload.appendUInt32(0xFFFF) // extra data refs that cannot fit
        #expect(throws: NIFError.self) {
            try NIFNode(data: payload, header: header())
        }
    }

    @Test func nonSkyrimStreamIsUnsupported() throws {
        // Non-Skyrim stream parses at container level but the scene-graph
        // layer only reads Skyrim layouts (83/100).
        var reader = BinaryReader(NIFFixture.header(bsVersion: 90))
        let header = try NIFHeader(reader: &reader)
        #expect(throws: NIFError.unsupported(
            "scene-graph decode needs a Skyrim BS stream (83/100), got 90"
        )) {
            try NIFNode(data: NIFFixture.niNode(), header: header)
        }
    }
}
