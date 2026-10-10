// MATT material type: the surface names that collision meshes (by name hash),
// LTEX.MNAM, and IPDS impact tables all key on.
// Layout and sources: docs/formats/material-type.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct MaterialType: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    /// MNAM — the Creation Kit material name. This is the string a NIF's Havok
    /// material value is the hash of, so a record without one can never be
    /// reached from a collision mesh.
    public let materialName: String?
    /// PNAM — the material this one inherits from, or nil at the root of a
    /// chain. Vanilla uses it to say that stairs-of-stone are stone.
    public let parent: FormID?
    /// HNAM — the impact data set to play on this material when the thing that
    /// struck it names none of its own. Footsteps do not read it: a footstep
    /// always carries its own IPDS through `FSTP.DATA`.
    public let impactDataSet: FormID?

    /// The value a NIF collision shape stores to point at this record, or nil
    /// when the record carries no name to hash.
    public var havokMaterial: UInt32? {
        materialName.map(HavokMaterialHash.value(ofMaterialName:))
    }

    /// CNAM — RGB the editor draws havok shapes of this material in, 0-1.
    public let havokDisplayColor: SIMD3<Float>?
    public let buoyancy: Float?
    /// FNAM bit 0 stair material, bit 1 arrows stick.
    public let flags: UInt32
    public let skipped: FieldTally

    public init(record: ESMRecord) throws {
        guard record.type == "MATT" else {
            throw ESMError.malformed("expected MATT record, got \(record.type)")
        }
        var rest = try RecordFields(record: record, type: "MATT")
        let recordID = rest.formID
        formID = recordID
        var editorID: String?
        var materialName: String?
        var parent: FormID?
        var impactDataSet: FormID?
        try rest.readEach { field in
            var reader = BinaryReader(field.data)
            switch field.type {
            case "EDID":
                editorID = try reader.readZString()
            case "MNAM":
                materialName = try reader.readZString()
            case "PNAM":
                parent = try Self.readLink(&reader, size: field.data.count)
            case "HNAM":
                impactDataSet = try Self.readLink(&reader, size: field.data.count)
            // Skipped: CNAM (Havok display colour, a Creation Kit affordance),
            // BNAM (buoyancy) and FNAM (stair/arrow flags). Nothing floats or
            // sticks arrows yet, and a field this decoder does not read cannot
            // go stale against the spec.
            default:
                return false
            }
            return true
        }
        havokDisplayColor = rest.read("CNAM") { try $0.readFloat3() }
        buoyancy = rest.float("BNAM")
        flags = rest.uint32("FNAM") ?? 0
        skipped = rest.finish()
        self.editorID = editorID
        self.materialName = materialName
        self.parent = parent
        self.impactDataSet = impactDataSet
    }

    /// Test seam: a material built from decoded values rather than a record.
    public init(
        formID: FormID,
        editorID: String? = nil,
        materialName: String?,
        parent: FormID? = nil,
        impactDataSet: FormID? = nil
    ) {
        self.formID = formID
        self.editorID = editorID
        self.materialName = materialName
        self.parent = parent
        self.impactDataSet = impactDataSet
        havokDisplayColor = nil
        buoyancy = nil
        flags = 0
        skipped = FieldTally()
    }

    private static func readLink(
        _ reader: inout BinaryReader,
        size: Int
    ) throws -> FormID? {
        guard size == 4 else { return nil }
        let id = try FormID(reader.readUInt32())
        return id.isNull ? nil : id
    }
}

/// The `PNAM` links of every material, walked from a child towards its root.
nonisolated public struct MaterialParents: Equatable, Sendable {
    /// Vanilla chains are two or three deep; a loop in a plugin stops here.
    public static let maximumDepth = 16

    private let parents: [UInt32: FormID]

    public init(parents: [FormID: FormID]) {
        self.parents = Dictionary(
            uniqueKeysWithValues: parents.map { ($0.key.rawValue, $0.value) }
        )
    }

    public init(materials: [MaterialType]) {
        var parents: [FormID: FormID] = [:]
        for material in materials {
            if let parent = material.parent, !parent.isNull {
                parents[material.formID] = parent
            }
        }
        self.init(parents: parents)
    }

    public static let empty = MaterialParents(parents: [:])

    /// `material` first, then its parent, its parent's parent, and so on. Empty for nil.
    public func chain(from material: FormID?) -> [FormID] {
        guard let material else { return [] }
        var chain = [material]
        while
            chain.count < Self.maximumDepth,
            let parent = parents[chain[chain.count - 1].rawValue],
            !chain.contains(parent)
        {
            chain.append(parent)
        }
        return chain
    }
}
