// XPRM primitive-volume decode on REFR, over synthetic bytes. XPRM is 32
// bytes: 3 bound floats, 3 color floats, an unknown float, a uint32 type.
// Layout: docs/formats/placed-references.md.

import FormatsCoreTesting
import FormatsESMTesting
import Foundation
@testable import OpenSkyFormatsESM
import Testing

struct PlacedReferenceXPRMTests {
    typealias PrimitiveType = PlacedReference.PrimitiveType

    /// Builds a 32-byte XPRM payload. `trailing` and `truncate` exist so the
    /// malformed cases stay one call away from the well-formed one.
    private func xprm(
        halfExtents: SIMD3<Float> = SIMD3(64, 128, 256),
        color: SIMD3<Float> = SIMD3(0.25, 0.5, 1),
        unknown: Float = 0.15,
        type: UInt32 = 1,
        trailing: Int = 0,
        truncate: Int = 0
    ) -> Data {
        var payload = Data()
        for value in [halfExtents.x, halfExtents.y, halfExtents.z] {
            payload.appendUInt32(value.bitPattern)
        }
        for value in [color.x, color.y, color.z] {
            payload.appendUInt32(value.bitPattern)
        }
        payload.appendUInt32(unknown.bitPattern)
        payload.appendUInt32(type)
        payload.append(Data(count: trailing))
        return ESMFixture.field("XPRM", payload.prefix(payload.count - truncate))
    }

    @Test func decodesEveryFieldOfAPrimitive() throws {
        let primitive = try #require(try PlacedReferenceFixture.reference(xprm()).primitive)
        #expect(primitive.halfExtents == SIMD3(64, 128, 256))
        #expect(primitive.color == SIMD3(0.25, 0.5, 1))
        #expect(primitive.unknown == 0.15)
        #expect(primitive.type == .box)
    }

    /// Every shape Skyrim.esm carries, plus the `none` value xEdit names but
    /// vanilla never writes. The raw values are the enum contract.
    @Test(arguments: [
        (UInt32(0), PrimitiveType.none),
        (UInt32(1), PrimitiveType.box),
        (UInt32(2), PrimitiveType.sphere),
        (UInt32(3), PrimitiveType.portalBox),
        (UInt32(4), PrimitiveType.line)
    ])
    func decodesEveryPrimitiveType(raw: UInt32, expected: PrimitiveType) throws {
        let refr = try PlacedReferenceFixture.reference(xprm(type: raw))
        #expect(refr.primitive?.type == expected)
        #expect(expected.rawValue == raw)
    }

    /// A zero axis is legal — Skyrim.esm has 129 of them — so a degenerate
    /// volume must decode rather than be rejected.
    @Test func keepsADegenerateHalfExtentAxis() throws {
        let refr = try PlacedReferenceFixture.reference(xprm(
            halfExtents: SIMD3(0, 32, 64),
            type: 4
        ))
        #expect(refr.primitive?.halfExtents == SIMD3<Float>(0, 32, 64))
        #expect(refr.primitive?.type == .line)
    }

    @Test func absentPrimitiveLeavesTheFieldNil() throws {
        let refr = try PlacedReferenceFixture.reference(Data())
        #expect(refr.primitive == nil)
        #expect(refr.base == FormID(0x0002_D4E2))
    }

    /// Unlike XLKR, a short payload throws: XPRM is one fixed-width struct, so
    /// a truncated read would shift every field.
    @Test func rejectsTruncatedPrimitive() throws {
        #expect(throws: ESMError.malformed("REFR 00001000 XPRM has 28 bytes, expected 32")) {
            _ = try PlacedReferenceFixture.reference(xprm(truncate: 4))
        }
    }

    @Test func rejectsOversizedPrimitive() throws {
        #expect(throws: ESMError.malformed("REFR 00001000 XPRM has 36 bytes, expected 32")) {
            _ = try PlacedReferenceFixture.reference(xprm(trailing: 4))
        }
    }

    @Test func rejectsPrimitiveTypeOutsideTheEnum() throws {
        #expect(throws: ESMError.malformed("REFR 00001000 XPRM has unknown type 5")) {
            _ = try PlacedReferenceFixture.reference(xprm(type: 5))
        }
    }

    /// XPRM must be matched before the VMAD catch-all, and adding the case
    /// must not steal script attachments from it.
    @Test func primitiveCoexistsWithScriptAttachments() throws {
        let script = VMADFixture.Script("OpenSkyProbe", properties: [])
        let vmad = ESMFixture.field("VMAD", VMADFixture.payload(scripts: [script]))
        let refr = try PlacedReferenceFixture.reference(vmad + xprm(type: 2))
        #expect(refr.primitive?.type == .sphere)
        #expect(refr.scriptData.scripts.map(\.name) == ["OpenSkyProbe"])
    }
}
