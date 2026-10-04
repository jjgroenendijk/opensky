// `NiTransformData` keyframes: the rotation and translation keys of one
// animated transform. Scale keys follow and are not read. Layout:
// docs/formats/nif.md#camera-animation.

import Foundation
import OpenSkyFormatsCore
import simd

/// One interpolation key. Quadratic tangents and TBC values are read past and
/// not kept: OpenSky samples every key type linearly.
nonisolated public struct NIFKey<Value: Equatable & Sendable>: Equatable, Sendable {
    public let time: Float
    public let value: Value

    public init(time: Float, value: Value) {
        self.time = time
        self.value = value
    }
}

nonisolated public enum NIFKeyType: UInt32, Equatable, Sendable {
    case linear = 1
    case quadratic = 2
    case tbc = 3
    case xyzRotation = 4
    case constant = 5
}

nonisolated public struct NIFTransformData: Equatable, Sendable {
    public static let typeName = "NiTransformData"

    public let rotationType: NIFKeyType?
    /// Quaternion keys, as `simd_quatf`. Empty for XYZ rotation data.
    public let rotations: [NIFKey<simd_quatf>]
    /// X, Y, and Z angle keys in radians, used when `rotationType` is `xyzRotation`.
    public let eulerRotations: [[NIFKey<Float>]]
    public let translations: [NIFKey<SIMD3<Float>>]

    public init(data: Data) throws {
        var reader = BinaryReader(data)
        let rotationCount = try Int(reader.readUInt32())
        var rotationType: NIFKeyType?
        var rotations: [NIFKey<simd_quatf>] = []
        var euler: [[NIFKey<Float>]] = []
        if rotationCount > 0 {
            let type = try Self.keyType(reader.readUInt32())
            rotationType = type
            if type == .xyzRotation {
                euler = try (0 ..< 3)
                    .map { _ in try Self.keyGroup(&reader) { try $0.readFloat32() } }
            } else {
                try Self.checkCount(rotationCount, stride: 20, reader)
                for _ in 0 ..< rotationCount {
                    let time = try reader.readFloat32()
                    let quaternion = try Self.readQuaternion(&reader)
                    if type == .tbc {
                        reader.skip(12)
                    }
                    rotations.append(NIFKey(time: time, value: quaternion))
                }
            }
        }
        self.rotationType = rotationType
        self.rotations = rotations
        eulerRotations = euler
        translations = try Self.keyGroup(&reader) { try $0.readVector3() }
    }

    /// nif.xml stores w first; `simd_quatf` takes the vector part first.
    static func readQuaternion(_ reader: inout BinaryReader) throws -> simd_quatf {
        let w = try reader.readFloat32()
        let vector = try reader.readVector3()
        return simd_quatf(ix: vector.x, iy: vector.y, iz: vector.z, r: w)
    }

    private static func keyGroup<Value>(
        _ reader: inout BinaryReader,
        value read: (inout BinaryReader) throws -> Value
    ) throws -> [NIFKey<Value>] {
        let count = try Int(reader.readUInt32())
        guard count > 0 else { return [] }
        let type = try keyType(reader.readUInt32())
        try checkCount(count, stride: 8, reader)
        var keys: [NIFKey<Value>] = []
        keys.reserveCapacity(count)
        for _ in 0 ..< count {
            let time = try reader.readFloat32()
            let value = try read(&reader)
            switch type {
            case .quadratic:
                _ = try read(&reader)
                _ = try read(&reader)
            case .tbc:
                reader.skip(12)
            case .linear, .constant, .xyzRotation:
                break
            }
            keys.append(NIFKey(time: time, value: value))
        }
        return keys
    }

    private static func keyType(_ raw: UInt32) throws -> NIFKeyType {
        guard let type = NIFKeyType(rawValue: raw) else {
            throw NIFError.malformed("unknown key type \(raw)")
        }
        return type
    }

    /// Rejects a count the block cannot hold, before allocating for it.
    private static func checkCount(_ count: Int, stride: Int, _ reader: BinaryReader) throws {
        guard count * stride <= reader.bytesRemaining else {
            throw NIFError.malformed("key count \(count) exceeds block size")
        }
    }
}
