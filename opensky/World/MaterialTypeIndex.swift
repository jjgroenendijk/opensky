// The two lookups that turn a surface into a MATT material type (issue #358).
//
// A collision mesh and a landscape quadrant name their material in different
// currencies. A NIF stores the hash of the Creation Kit material name; a LAND
// quadrant stores an LTEX FormID whose MNAM points at the MATT directly. Both
// arrive here and leave as the same MATT FormID, so everything downstream —
// the collision world, the ground contact, the impact table — speaks one
// language.
//
// Built once per plugin and read from the build queue like the other record
// indexes, which is why it is an immutable value rather than a cache.

import OSLog

nonisolated struct MaterialTypeIndex: Sendable {
    static let logger = Logger(
        subsystem: "nl.jjgroenendijk.opensky",
        category: "MaterialType"
    )

    /// Every decoded MATT, by FormID.
    let materials: [UInt32: MaterialType]
    /// Havok material value -> MATT. Only the materials that carry an MNAM to
    /// hash appear; a mesh naming any other value resolves to nothing.
    private let byHavokMaterial: [UInt32: FormID]
    /// LTEX FormID -> MATT, from LTEX.MNAM.
    private let byLandTexture: [UInt32: FormID]

    static let empty = MaterialTypeIndex(materials: [], landTextureMaterials: [:])

    init(file: ESMFile) {
        var materials: [MaterialType] = []
        if let group = file.topGroup(of: "MATT"), let children = try? group.children() {
            for case let .record(record) in children where record.type == "MATT" {
                guard !record.isDeleted else { continue }
                guard let material = try? MaterialType(record: record) else {
                    let id = FormID(record.formID).description
                    Self.logger.warning("malformed MATT \(id, privacy: .public) skipped")
                    continue
                }
                materials.append(material)
            }
        }
        var landTextures: [FormID: FormID] = [:]
        if let group = file.topGroup(of: "LTEX"), let children = try? group.children() {
            for case let .record(record) in children where record.type == "LTEX" {
                guard !record.isDeleted, let texture = try? LandTexture(record: record) else {
                    continue
                }
                landTextures[texture.formID] = texture.materialType
            }
        }
        self.init(materials: materials, landTextureMaterials: landTextures)
    }

    /// Test seam, and the shape the file initializer funnels into.
    ///
    /// `landTextureMaterials` carries optional values so that an LTEX which
    /// names no material is still a known texture rather than an absent one.
    init(materials: [MaterialType], landTextureMaterials: [FormID: FormID?]) {
        self.materials = Dictionary(
            materials.map { ($0.formID.rawValue, $0) },
            // Two MATT records cannot share a FormID in a well-formed plugin;
            // if a modded load order manages it, record order decides.
            uniquingKeysWith: { first, _ in first }
        )
        byHavokMaterial = Dictionary(
            materials.compactMap { material in
                material.havokMaterial.map { ($0, material.formID) }
            },
            // Two materials whose names hash alike would be indistinguishable
            // to the game engine too, so the first in record order wins here
            // exactly as it would there.
            uniquingKeysWith: { first, _ in first }
        )
        byLandTexture = landTextureMaterials.reduce(into: [:]) { result, entry in
            if let material = entry.value {
                result[entry.key.rawValue] = material
            }
        }
    }

    var isEmpty: Bool {
        materials.isEmpty
    }

    /// How many materials can be reached from a collision mesh at all.
    var hashedMaterialCount: Int {
        byHavokMaterial.count
    }

    func material(_ id: FormID) -> MaterialType? {
        materials[id.rawValue]
    }

    /// The MATT a NIF collision shape's Havok material value names. Nil for a
    /// value no loaded MATT hashes to, which is normal: vanilla meshes carry
    /// materials the Creation Kit no longer lists (nif.xml documents several as
    /// unknown), and a footstep on one falls back the same way an unresolved
    /// surface always has.
    func material(forHavokMaterial value: UInt32) -> FormID? {
        byHavokMaterial[value]
    }

    /// The MATT an LTEX names through its MNAM, for the terrain half of the
    /// chain. Exterior ground is LAND rather than a collision mesh, so its
    /// material comes from the winning landscape texture instead of Havok.
    func material(forLandTexture id: FormID) -> FormID? {
        byLandTexture[id.rawValue]
    }

    /// How a readout names a material: its editor ID, else its Creation Kit
    /// name, else the FormID.
    func describe(_ id: FormID) -> String {
        guard let material = material(id) else { return id.description }
        return material.editorID ?? material.materialName ?? id.description
    }
}
