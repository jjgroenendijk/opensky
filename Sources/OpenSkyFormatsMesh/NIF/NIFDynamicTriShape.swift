// BSDynamicTriShape: a full BSTriShape payload, then a uint32 byte size and
// one Vector4 per vertex. FaceGen bakes current positions there: xyz replaces
// the inherited positions, w is runtime-only. Layout: docs/formats/nif.md.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFDynamicTriShape: Sendable {
    public let shape: NIFTriShape

    public init(data: Data, header: NIFHeader) throws {
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
