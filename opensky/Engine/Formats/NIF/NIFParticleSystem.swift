// NiParticleSystem (+ BSStripParticleSystem, identical layout) block parser.
// Inheritance NiAVObject -> NiGeometry -> NiParticles -> NiParticleSystem. For
// Bethesda 20.2 NIFs NiParticles switched to a BSGeometry-style layout, so
// nif.xml doubles up the NiGeometry rows by stream: BS stream 100 (SSE) carries
// a bounding sphere + skin ref + inline BSVertexDesc and takes its NiPSysData
// ref from NiParticleSystem.Data, while stream 83 (Skyrim LE) keeps the classic
// NiGeometry Data/Skin-Instance/Material-Data run and has no vertex desc. Skin,
// material data, and the LOD Far/Near cull shorts are read past but not kept —
// static decode needs only the data ref, world-space flag, shader/alpha refs,
// and the modifier ref list. Controllers are skipped like NiObjectNET does.
//
// Reference: NifTools nif.xml (NiGeometry, NiParticles, NiParticleSystem,
// BSStripParticleSystem, NiBound, BSVertexDesc, MaterialData; vercond tokens
// BS_GTE_SSE, NI_BS_LT_SSE, BS_GT_FO3, BS_GTE_SKY).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif-particles.md.

import Foundation
import simd

nonisolated struct NIFParticleSystem {
    let object: NIFObjectPrefix
    /// NiPSysData block ref; -1 = none. Source differs by stream (see file
    /// header comment) but the resolved ref is the same either way.
    let dataRef: Int32
    let shaderPropertyRef: Int32
    let alphaPropertyRef: Int32
    /// nif.xml World Space (default true).
    let worldSpace: Bool
    /// NiPSysModifier block refs in chain order; -1 entries kept positional.
    let modifierRefs: [Int32]

    init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        let streamVersion = header.bsStream?.version ?? 0
        guard streamVersion == 83 || streamVersion == 100 else {
            throw NIFError.unsupported(
                "NiParticleSystem needs a Skyrim BS stream (83/100), got \(streamVersion)"
            )
        }
        object = try NIFObjectPrefix(reader: &reader, header: header)

        if streamVersion >= 100 {
            // NiGeometry (SSE / BSGeometry rows): bounding sphere, skin ref,
            // then shader + alpha refs. The NiPSysData ref comes later, inside
            // the NiParticleSystem fields.
            reader.skip(16) // NiBound: center (Vector3) + radius (float)
            reader.skip(4) // Skin ref, unused (skinned particles out of scope)
            shaderPropertyRef = try Int32(bitPattern: reader.readUInt32())
            alphaPropertyRef = try Int32(bitPattern: reader.readUInt32())
            reader.skip(8) // BSVertexDesc, unused by static decode
            reader.skip(8) // Far/Near begin+end cull shorts
            dataRef = try Int32(bitPattern: reader.readUInt32())
        } else {
            // NiGeometry (classic rows): data ref, skin instance, material
            // data, then shader + alpha refs. No inline vertex desc.
            dataRef = try Int32(bitPattern: reader.readUInt32())
            reader.skip(4) // Skin Instance ref, unused
            try Self.skipMaterialData(&reader)
            shaderPropertyRef = try Int32(bitPattern: reader.readUInt32())
            alphaPropertyRef = try Int32(bitPattern: reader.readUInt32())
            reader.skip(8) // Far/Near begin+end cull shorts
        }

        worldSpace = try reader.readUInt8() != 0
        let modifierCount = try Int(reader.readUInt32())
        guard modifierCount >= 0, modifierCount * 4 <= reader.bytesRemaining else {
            throw NIFError.malformed(
                "modifier count \(modifierCount) exceeds block size"
            )
        }
        var refs: [Int32] = []
        refs.reserveCapacity(modifierCount)
        for _ in 0 ..< modifierCount {
            try refs.append(Int32(bitPattern: reader.readUInt32()))
        }
        modifierRefs = refs
    }

    /// nif.xml MaterialData for version 20.2.0.7: material name/extra-data
    /// arrays framed by a count, an active-material index, then the
    /// needs-update flag. All ignored for static decode; only its length
    /// matters so the reader lands on the shader ref.
    private static func skipMaterialData(_ reader: inout BinaryReader) throws {
        let materialCount = try Int(reader.readUInt32())
        // Name (NiFixedString) + extra-data (int), 4 bytes each per material.
        guard materialCount >= 0, materialCount * 8 <= reader.bytesRemaining else {
            throw NIFError.malformed(
                "material count \(materialCount) exceeds block size"
            )
        }
        reader.skip(materialCount * 8)
        reader.skip(4) // Active Material index
        reader.skip(1) // Material Needs Update flag
    }
}
