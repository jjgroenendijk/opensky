// Skyrim SE BSDynamicTriShape: complete inherited BSTriShape payload plus
// uint32 byte size + one Vector4 per vertex. FaceGen stores baked current
// positions here; xyz replaces inherited positions, w stays runtime-only.
//
// Reference: NifTools nif.xml at 292bb94 (BSDynamicTriShape, BS stream 100).
//   https://github.com/niftools/nifxml/blob/292bb9403cbf4052c58d66e80906b6bde1700779/nif.xml
// Layout documented in docs/formats/nif.md.

import Foundation
import simd

nonisolated struct NIFDynamicTriShape {
    let shape: NIFTriShape

    init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        let inherited = try NIFTriShape(reader: &reader, header: header)
        let byteCount = try Int(reader.readUInt32())
        guard
            byteCount == inherited.vertexCount * 16,
            byteCount <= reader.bytesRemaining
        else {
            throw NIFError.malformed(
                "dynamic vertex size \(byteCount) != \(inherited.vertexCount) vertices * 16"
            )
        }
        var positions: [SIMD3<Float>] = []
        positions.reserveCapacity(inherited.vertexCount)
        for _ in 0 ..< inherited.vertexCount {
            let value = try SIMD4<Float>(
                reader.readFloat32(), reader.readFloat32(),
                reader.readFloat32(), reader.readFloat32()
            )
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite, value.w.isFinite else {
                throw NIFError.malformed("dynamic vertex contains a non-finite value")
            }
            positions.append(value.xyz)
        }
        shape = NIFTriShape(replacingPositions: positions, in: inherited)
    }
}
