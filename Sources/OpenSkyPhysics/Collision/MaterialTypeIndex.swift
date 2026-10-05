// Turns a surface into a MATT material type. A NIF names its material by the
// hash of the Creation Kit name; a LAND quadrant names an LTEX whose MNAM is the
// MATT. Both lookups return the same MATT FormID.

import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OSLog

nonisolated public struct MaterialTypeIndex: Sendable {
    public static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "MaterialType"
    )

    public let materials: [UInt32: MaterialType]
    /// Havok material value -> MATT, for materials with an MNAM to hash.
    private let byHavokMaterial: [UInt32: FormID]
    /// LTEX FormID -> MATT, from LTEX.MNAM.
    private let byLandTexture: [UInt32: FormID]
    public let skippedRecords: SkippedRecords

    public static let empty = MaterialTypeIndex(materials: [], landTextureMaterials: [:])

    public init(file: ESMFile) {
        var skipped = SkippedRecords()
        let materials = file.decodeRecords(of: "MATT", skipped: &skipped) {
            try MaterialType(record: $0)
        }
        let textures = file.decodeRecords(of: "LTEX", skipped: &skipped) {
            try LandTexture(record: $0)
        }
        self.init(
            materials: materials,
            landTextureMaterials: LandTexture.index(textures).reduce(into: [:]) { result, entry in
                result[FormID(entry.key)] = entry.value.materialType
            },
            skippedRecords: skipped
        )
        for line in skipped.lines {
            Self.logger.warning("\(line, privacy: .public)")
        }
    }

    /// Test seam. A nil value keeps an LTEX with no MNAM known.
    public init(
        materials: [MaterialType],
        landTextureMaterials: [FormID: FormID?],
        skippedRecords: SkippedRecords = SkippedRecords()
    ) {
        self.skippedRecords = skippedRecords
        self.materials = Dictionary(
            materials.map { ($0.formID.rawValue, $0) },
            // A duplicate FormID is malformed; record order decides.
            uniquingKeysWith: { first, _ in first }
        )
        byHavokMaterial = Dictionary(
            materials.compactMap { material in
                material.havokMaterial.map { ($0, material.formID) }
            },
            // Names that hash alike collide in the game too; the first wins.
            uniquingKeysWith: { first, _ in first }
        )
        byLandTexture = landTextureMaterials.reduce(into: [:]) { result, entry in
            if let material = entry.value {
                result[entry.key.rawValue] = material
            }
        }
    }

    public var isEmpty: Bool {
        materials.isEmpty
    }

    /// How many materials can be reached from a collision mesh at all.
    public var hashedMaterialCount: Int {
        byHavokMaterial.count
    }

    public func material(_ id: FormID) -> MaterialType? {
        materials[id.rawValue]
    }

    /// The MATT a NIF Havok material value names. Nil is normal: vanilla meshes
    /// carry materials no MATT lists.
    public func material(forHavokMaterial value: UInt32) -> FormID? {
        byHavokMaterial[value]
    }

    /// The MATT an LTEX names through its MNAM, for exterior ground.
    public func material(forLandTexture id: FormID) -> FormID? {
        byLandTexture[id.rawValue]
    }

    /// Editor ID, else Creation Kit name, else FormID.
    public func describe(_ id: FormID) -> String {
        guard let material = material(id) else { return id.description }
        return material.editorID ?? material.materialName ?? id.description
    }
}
