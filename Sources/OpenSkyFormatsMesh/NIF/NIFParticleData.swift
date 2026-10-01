// NiPSysData and BSStripPSysData. Under BS202 the per-particle arrays have no
// length on disk, because the simulation allocates them. So only capacity,
// presence flags, and atlas offsets are kept.
// Layout: docs/formats/nif-particles.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFParticleData: Sendable {
    /// nif.xml "BS Max Vertices": max simultaneous particles (capacity).
    public let maxParticles: Int
    public let hasRadii: Bool
    public let hasSizes: Bool
    public let hasRotations: Bool
    public let hasRotationAngles: Bool
    public let hasRotationAxes: Bool
    public let hasRotationSpeeds: Bool
    public let hasTextureIndices: Bool
    /// UV atlas quads for BSPSysSubTexModifier; empty when unused.
    public let subtextureOffsets: [SIMD4<Float>]
    /// BSStripPSysData "Max Point Count"; nil for a plain NiPSysData.
    public let maxPointCount: Int?

    public init(data: Data, header: NIFHeader, isStrip: Bool = false) throws {
        var reader = BinaryReader(data)
        let streamVersion = header.bsStream?.version ?? 0
        // BS202 = file version 20.2.0.7 with a Bethesda stream; both Skyrim
        // streams qualify and share this layout.
        guard streamVersion == 83 || streamVersion == 100 else {
            throw NIFError.unsupported(
                "NiPSysData needs a Skyrim BS stream (83/100), got \(streamVersion)"
            )
        }

        // NiGeometryData (BS202, NiPSysData variant).
        reader.skip(4) // Group ID
        maxParticles = try Int(reader.readUInt16()) // BS Max Vertices
        reader.skip(2) // Keep Flags + Compress Flags
        reader.skip(1) // Has Vertices (arrays have no length under BS202)
        reader.skip(2) // BS Data Flags
        reader.skip(4) // Material CRC
        reader.skip(1) // Has Normals
        reader.skip(16) // Bounding Sphere (NiBound)
        reader.skip(1) // Has Vertex Colors
        reader.skip(2) // Consistency Flags
        reader.skip(4) // Additional Data ref

        // NiParticlesData (BS202).
        hasRadii = try reader.readUInt8() != 0
        reader.skip(2) // Num Active
        hasSizes = try reader.readUInt8() != 0
        hasRotations = try reader.readUInt8() != 0
        hasRotationAngles = try reader.readUInt8() != 0
        hasRotationAxes = try reader.readUInt8() != 0
        hasTextureIndices = try reader.readUInt8() != 0
        let subtextureCount = try Int(reader.readUInt32())
        guard subtextureCount >= 0, subtextureCount * 16 <= reader.bytesRemaining else {
            throw NIFError.malformed(
                "subtexture offset count \(subtextureCount) exceeds block size"
            )
        }
        var offsets: [SIMD4<Float>] = []
        offsets.reserveCapacity(subtextureCount)
        for _ in 0 ..< subtextureCount {
            try offsets.append(SIMD4(
                reader.readFloat32(), reader.readFloat32(),
                reader.readFloat32(), reader.readFloat32()
            ))
        }
        subtextureOffsets = offsets
        reader.skip(4) // Aspect Ratio
        reader.skip(2) // Aspect Flags
        reader.skip(12) // Speed-to-Aspect: aspect 2 + speed 1 + speed 2

        // NiPSysData (BS202): only the rotation-speed presence byte survives;
        // Particle Info / added-particle counts are all excluded under BS202.
        hasRotationSpeeds = try reader.readUInt8() != 0

        if isStrip {
            // BSStripPSysData appends strip-mesh fields after NiPSysData.
            maxPointCount = try Int(reader.readUInt16())
            reader.skip(4) // Start Cap Size
            reader.skip(4) // End Cap Size
            reader.skip(1) // Do Z Prepass
        } else {
            maxPointCount = nil
        }
    }
}
