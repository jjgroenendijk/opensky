// Skyrim FaceGen TRI expression container. The clean engine type retains the
// base topology plus named, scaled per-vertex deltas; UVs, chargen modifiers
// and absolute modifier vertices are validated and skipped because expression
// playback does not consume them.
//
// Reference: NifTools PyFFI `tri.xml` and `pyffi.formats.tri`.
// https://github.com/niftools/pyffi/blob/master/pyffi/formats/tri/tri.xml
// Confirmed against the user's install at runtime; see docs/formats/tri.md.

import Foundation
import simd

nonisolated enum TRIError: Error, Equatable {
    case malformed(String)
    case unsupportedVersion(String)
}

nonisolated struct TRITriangle: Equatable {
    let vertices: SIMD3<UInt32>
}

nonisolated struct TRIMorphTarget: Equatable {
    let name: String
    /// Multiplier applied to each signed-integer delta component.
    let scale: Float
    /// Signed on-disk components widened to Float, one per base vertex.
    let deltas: [SIMD3<Float>]

    var scaledDeltas: [SIMD3<Float>] {
        deltas.map { $0 * scale }
    }
}

nonisolated struct TRIFile: Equatable {
    let baseVertices: [SIMD3<Float>]
    let triangles: [TRITriangle]
    let morphTargets: [TRIMorphTarget]

    init(data: Data) throws {
        do {
            var decoder = TRIDecoder(data: data)
            let decoded = try decoder.decode()
            baseVertices = decoded.baseVertices
            triangles = decoded.triangles
            morphTargets = decoded.morphTargets
        } catch let error as TRIError {
            throw error
        } catch {
            throw TRIError.malformed(String(describing: error))
        }
    }

    init(
        baseVertices: [SIMD3<Float>],
        triangles: [TRITriangle],
        morphTargets: [TRIMorphTarget]
    ) {
        self.baseVertices = baseVertices
        self.triangles = triangles
        self.morphTargets = morphTargets
    }

    func target(named name: String) -> TRIMorphTarget? {
        morphTargets.first { $0.name == name }
    }
}

nonisolated private struct TRIHeader {
    let vertexCount: Int
    let triangleCount: Int
    let quadCount: Int
    let uvCount: Int
    let hasUV: Bool
    let morphCount: Int
    let modifierCount: Int
    let modifierVertexCount: Int
}

nonisolated private struct TRIDecoder {
    private static let headerSize = 64
    private var reader: BinaryReader

    init(data: Data) {
        reader = BinaryReader(data)
    }

    mutating func decode() throws -> TRIFile {
        let header = try readHeader()
        let vertices = try readVertices(count: header.vertexCount, label: "base vertices")
        _ = try readVertices(count: header.modifierVertexCount, label: "modifier vertices")
        let triangles = try readTriangles(
            count: header.triangleCount, vertexCount: header.vertexCount
        )
        try skipQuadFaces(count: header.quadCount, vertexCount: header.vertexCount)
        try skipUVs(count: header.uvCount)
        if header.hasUV {
            try skipFaceBytes(triangles: header.triangleCount, quads: header.quadCount)
        }
        let morphs = try readMorphs(
            count: header.morphCount, vertexCount: header.vertexCount
        )
        try skipModifiers(count: header.modifierCount, vertexCount: header.vertexCount)
        guard reader.bytesRemaining == 0 else {
            throw TRIError.malformed("\(reader.bytesRemaining) trailing bytes")
        }
        return TRIFile(
            baseVertices: vertices,
            triangles: triangles,
            morphTargets: morphs
        )
    }

    private mutating func readHeader() throws -> TRIHeader {
        guard reader.bytesRemaining >= Self.headerSize else {
            throw TRIError.malformed("file is shorter than the 64-byte header")
        }
        let signature = try reader.read(count: 5)
        guard signature == Data("FRTRI".utf8) else {
            throw TRIError.malformed("signature is not FRTRI")
        }
        let versionData = try reader.read(count: 3)
        let version = String(data: versionData, encoding: .ascii) ?? "<invalid>"
        guard version == "003" else { throw TRIError.unsupportedVersion(version) }
        let vertexCount = try readCount("vertices")
        let triangleCount = try readCount("triangles")
        let quadCount = try readCount("quads")
        _ = try readInteger()
        _ = try readInteger()
        let uvCount = try readCount("UVs")
        let hasUVValue = try readInteger()
        guard hasUVValue == 0 || hasUVValue == 1 else {
            throw TRIError.malformed("Has UV is \(hasUVValue), expected 0 or 1")
        }
        let morphCount = try readCount("morphs")
        let modifierCount = try readCount("modifiers")
        let modifierVertexCount = try readCount("modifier vertices")
        for _ in 0 ..< 4 {
            _ = try readInteger()
        }
        return TRIHeader(
            vertexCount: vertexCount,
            triangleCount: triangleCount,
            quadCount: quadCount,
            uvCount: uvCount,
            hasUV: hasUVValue == 1,
            morphCount: morphCount,
            modifierCount: modifierCount,
            modifierVertexCount: modifierVertexCount
        )
    }

    private mutating func readVertices(count: Int, label: String) throws -> [SIMD3<Float>] {
        try requireBytes(count: count, stride: 12, label: label)
        var values: [SIMD3<Float>] = []
        values.reserveCapacity(count)
        for _ in 0 ..< count {
            let value = try SIMD3(
                reader.readFloat32(), reader.readFloat32(), reader.readFloat32()
            )
            guard value.x.isFinite, value.y.isFinite, value.z.isFinite else {
                throw TRIError.malformed("\(label) contain a non-finite component")
            }
            values.append(value)
        }
        return values
    }

    private mutating func readTriangles(
        count: Int,
        vertexCount: Int
    ) throws -> [TRITriangle] {
        try requireBytes(count: count, stride: 12, label: "triangle faces")
        var result: [TRITriangle] = []
        result.reserveCapacity(count)
        for _ in 0 ..< count {
            let indices = try SIMD3(readIndex(), readIndex(), readIndex())
            try validate(indices: [indices.x, indices.y, indices.z], count: vertexCount)
            result.append(TRITriangle(vertices: indices))
        }
        return result
    }

    private mutating func skipQuadFaces(count: Int, vertexCount: Int) throws {
        try requireBytes(count: count, stride: 16, label: "quad faces")
        for _ in 0 ..< count {
            let indices = try [readIndex(), readIndex(), readIndex(), readIndex()]
            try validate(indices: indices, count: vertexCount)
        }
    }

    private mutating func skipUVs(count: Int) throws {
        try requireBytes(count: count, stride: 8, label: "UVs")
        for _ in 0 ..< count {
            let u = try reader.readFloat32()
            let v = try reader.readFloat32()
            guard u.isFinite, v.isFinite else {
                throw TRIError.malformed("UVs contain a non-finite component")
            }
        }
    }

    private mutating func skipFaceBytes(triangles: Int, quads: Int) throws {
        let triangleBytes = try checkedProduct(triangles, 12, label: "UV triangle faces")
        let quadBytes = try checkedProduct(quads, 16, label: "UV quad faces")
        _ = try reader.read(count: triangleBytes + quadBytes)
    }

    private mutating func readMorphs(
        count: Int,
        vertexCount: Int
    ) throws -> [TRIMorphTarget] {
        guard count <= reader.bytesRemaining / 9 else {
            throw TRIError.malformed("morph count \(count) exceeds remaining bytes")
        }
        var targets: [TRIMorphTarget] = []
        targets.reserveCapacity(count)
        for _ in 0 ..< count {
            let name = try readSizedString()
            let scale = try reader.readFloat32()
            guard scale.isFinite else {
                throw TRIError.malformed("morph \(name) has a non-finite scale")
            }
            try requireBytes(count: vertexCount, stride: 6, label: "morph \(name) deltas")
            var deltas: [SIMD3<Float>] = []
            deltas.reserveCapacity(vertexCount)
            for _ in 0 ..< vertexCount {
                try deltas.append(SIMD3(
                    Float(readInt16()), Float(readInt16()), Float(readInt16())
                ))
            }
            targets.append(TRIMorphTarget(name: name, scale: scale, deltas: deltas))
        }
        return targets
    }

    private mutating func skipModifiers(count: Int, vertexCount: Int) throws {
        guard count <= reader.bytesRemaining / 8 else {
            throw TRIError.malformed("modifier count \(count) exceeds remaining bytes")
        }
        for _ in 0 ..< count {
            _ = try readSizedString()
            let indexCount = try readCount("modifier indices")
            try requireBytes(count: indexCount, stride: 4, label: "modifier indices")
            for _ in 0 ..< indexCount {
                try validate(indices: [readIndex()], count: vertexCount)
            }
        }
    }

    private mutating func readSizedString() throws -> String {
        let length = try Int(reader.readUInt32())
        guard length > 0, length <= reader.bytesRemaining else {
            throw TRIError.malformed("invalid sized-string length \(length)")
        }
        let bytes = try reader.read(count: length)
        guard bytes.last == 0 else {
            throw TRIError.malformed("sized string is not null terminated")
        }
        guard let value = String(data: Data(bytes.dropLast()), encoding: .utf8) else {
            throw TRIError.malformed("sized string is not UTF-8")
        }
        return value
    }

    private mutating func readCount(_ label: String) throws -> Int {
        let value = try readInteger()
        guard value >= 0 else { throw TRIError.malformed("negative \(label) count \(value)") }
        return Int(value)
    }

    private mutating func readInteger() throws -> Int32 {
        try Int32(bitPattern: reader.readUInt32())
    }

    private mutating func readInt16() throws -> Int16 {
        try Int16(bitPattern: reader.readUInt16())
    }

    private mutating func readIndex() throws -> UInt32 {
        let value = try readInteger()
        guard value >= 0 else { throw TRIError.malformed("negative vertex index \(value)") }
        return UInt32(value)
    }

    private func validate(indices: [UInt32], count: Int) throws {
        if let invalid = indices.first(where: { Int($0) >= count }) {
            throw TRIError.malformed("vertex index \(invalid) exceeds count \(count)")
        }
    }

    private mutating func requireBytes(count: Int, stride: Int, label: String) throws {
        let bytes = try checkedProduct(count, stride, label: label)
        guard bytes <= reader.bytesRemaining else {
            throw TRIError.malformed(
                "\(label) need \(bytes) bytes, only \(reader.bytesRemaining) remain"
            )
        }
    }

    private func checkedProduct(_ count: Int, _ stride: Int, label: String) throws -> Int {
        let (bytes, overflow) = count.multipliedReportingOverflow(by: stride)
        guard !overflow else { throw TRIError.malformed("\(label) byte count overflows") }
        return bytes
    }
}
