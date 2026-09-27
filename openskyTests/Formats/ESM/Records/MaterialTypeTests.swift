// MATT decoding and the two lookups into it (issue #358): a NIF's Havok
// material value, and an LTEX's MNAM. Synthetic records only.

import Foundation
@testable import opensky
import Testing

struct MaterialTypeTests {
    @Test func decodesEveryFieldTheChainReads() throws {
        let record = try Self.record(
            formID: 0x100,
            editorID: "MaterialSnow",
            materialName: "Snow",
            parent: 0x101,
            impactDataSet: 0x200
        )

        let material = try MaterialType(record: record)
        #expect(material.formID == FormID(0x100))
        #expect(material.editorID == "MaterialSnow")
        #expect(material.materialName == "Snow")
        #expect(material.parent == FormID(0x101))
        #expect(material.impactDataSet == FormID(0x200))
        #expect(material.havokMaterial == 398_949_039)
    }

    @Test func aNullLinkDecodesAsNoLink() throws {
        let record = try Self.record(
            formID: 0x100,
            editorID: "MaterialSnow",
            materialName: "Snow",
            parent: 0,
            impactDataSet: 0
        )

        let material = try MaterialType(record: record)
        #expect(material.parent == nil)
        #expect(material.impactDataSet == nil)
    }

    @Test func aMaterialWithNoNameCannotBeReachedFromAMesh() throws {
        let record = try Self.record(formID: 0x100, editorID: "MaterialNameless")

        #expect(try MaterialType(record: record).havokMaterial == nil)
    }

    @Test func theWrongRecordTypeThrows() throws {
        let record = try Self.parse(ESMFixture.record("IPCT", formID: 0x100, data: Data()))

        #expect(throws: (any Error).self) { try MaterialType(record: record) }
    }

    @Test func indexResolvesAMeshMaterialThroughTheHash() {
        let index = Self.index

        #expect(index.material(forHavokMaterial: 398_949_039) == FormID(0x101))
        #expect(index.material(forHavokMaterial: 3_741_512_247) == FormID(0x102))
        // A value no loaded material hashes to resolves to nothing rather than
        // to an arbitrary neighbour.
        #expect(index.material(forHavokMaterial: 1) == nil)
    }

    @Test func indexResolvesTerrainThroughTheLandTexture() {
        let index = Self.index

        #expect(index.material(forLandTexture: FormID(0x300)) == FormID(0x101))
        #expect(index.material(forLandTexture: FormID(0x301)) == nil)
        #expect(index.material(forLandTexture: FormID(0x999)) == nil)
    }

    @Test func indexNamesAMaterialForTheReadout() {
        let index = Self.index

        #expect(index.describe(FormID(0x101)) == "MaterialSnow")
        // No editor ID -> the Creation Kit name; neither -> the FormID.
        #expect(index.describe(FormID(0x103)) == "Gravel")
        #expect(index.describe(FormID(0x999)) == FormID(0x999).description)
    }

    @Test func anUnnamedMaterialDoesNotOccupyTheHashTable() {
        #expect(Self.index.hashedMaterialCount == 3)
    }

    static let index = MaterialTypeIndex(
        materials: [
            MaterialType(formID: FormID(0x101), editorID: "MaterialSnow", materialName: "Snow"),
            MaterialType(formID: FormID(0x102), editorID: "MaterialStone", materialName: "Stone"),
            MaterialType(formID: FormID(0x103), materialName: "Gravel"),
            MaterialType(formID: FormID(0x104), editorID: "MaterialNone", materialName: nil)
        ],
        landTextureMaterials: [
            FormID(0x300): FormID(0x101),
            FormID(0x301): nil
        ]
    )

    private static func record(
        formID: UInt32,
        editorID: String,
        materialName: String? = nil,
        parent: UInt32? = nil,
        impactDataSet: UInt32? = nil
    ) throws -> ESMRecord {
        var fields = ESMFixture.field("EDID", ESMFixture.zstring(editorID))
        if let materialName {
            fields += ESMFixture.field("MNAM", ESMFixture.zstring(materialName))
        }
        if let parent {
            fields += ESMFixture.field("PNAM", Self.uint32(parent))
        }
        if let impactDataSet {
            fields += ESMFixture.field("HNAM", Self.uint32(impactDataSet))
        }
        return try parse(ESMFixture.record("MATT", formID: formID, data: fields))
    }

    /// One synthetic record through the container walk, like the other record
    /// decoder tests.
    private static func parse(_ bytes: Data) throws -> ESMRecord {
        let children = try ESMGroup.parseChildren(in: bytes, range: 0 ..< bytes.count)
        guard case let .record(record)? = children.first else {
            throw ESMError.malformed("fixture did not produce a record")
        }
        return record
    }

    private static func uint32(_ value: UInt32) -> Data {
        withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
}
