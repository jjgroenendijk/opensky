// `NiExtraData` blocks: named values a scene object carries, such as the root's
// `BSX` flags, the `INV` inventory marker, or the `BBX` bound of a skeleton.
// Layout: docs/formats/nif-extra-data.md.

import Foundation
import OpenSkyFormatsCore
import simd

/// One extra data block: its name and its decoded value.
nonisolated public struct NIFExtraData: Equatable, Sendable {
    public let name: String?
    public let value: Value

    public init(name: String?, value: Value) {
        self.name = name
        self.value = value
    }

    public enum Value: Equatable, Sendable {
        case integer(UInt32)
        case flags(NIFBSXFlags)
        case float(Float)
        case boolean(Bool)
        case strings([String])
        case binary(Data)
        case inventoryMarker(NIFInventoryMarker)
        /// `BSBound`: a box by its centre and half its size on each axis.
        case bound(center: SIMD3<Float>, halfExtents: SIMD3<Float>)
        /// `BSDistantObjectLargeRefExtraData`.
        case largeReference(Bool)
        case decalPlacement(NIFDecalPlacement)
        case boneLOD([NIFBoneLOD])
    }
}

/// nif.xml `BSXFlags`: what the game sets up for a model it loads.
nonisolated public struct NIFBSXFlags: OptionSet, Equatable, Sendable {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public static let animated = Self(rawValue: 1 << 0)
    public static let havok = Self(rawValue: 1 << 1)
    public static let ragdoll = Self(rawValue: 1 << 2)
    public static let complex = Self(rawValue: 1 << 3)
    /// The model holds add-on nodes (`BSValueNode`), such as flames.
    public static let addon = Self(rawValue: 1 << 4)
    public static let editorMarker = Self(rawValue: 1 << 5)
    public static let dynamic = Self(rawValue: 1 << 6)
    public static let articulated = Self(rawValue: 1 << 7)
    public static let needsTransformUpdates = Self(rawValue: 1 << 8)
    public static let externalEmittance = Self(rawValue: 1 << 9)
    public static let magicShaderParticles = Self(rawValue: 1 << 10)
    public static let lights = Self(rawValue: 1 << 11)
    public static let breakable = Self(rawValue: 1 << 12)
}

/// `BSInvMarker`: how the inventory turns and zooms the model.
nonisolated public struct NIFInventoryMarker: Equatable, Sendable {
    /// Radians about X, Y, and Z. The file stores thousandths of a radian.
    public let rotation: SIMD3<Float>
    public let zoom: Float

    public init(rotation: SIMD3<Float>, zoom: Float) {
        self.rotation = rotation
        self.zoom = zoom
    }

    /// The marker's turn for column vectors. NIF matrices act on row vectors, so
    /// the angles turn the other way (docs/formats/nif-extra-data.md).
    public var orientation: simd_quatf {
        simd_quatf(angle: -rotation.z, axis: SIMD3(0, 0, 1))
            * simd_quatf(angle: -rotation.y, axis: SIMD3(0, 1, 0))
            * simd_quatf(angle: -rotation.x, axis: SIMD3(1, 0, 0))
    }
}

/// `BSDecalPlacementVectorExtraData`: points with normals where decals may go.
nonisolated public struct NIFDecalPlacement: Equatable, Sendable {
    public let value: Float
    public let points: [SIMD3<Float>]
    public let normals: [SIMD3<Float>]

    public init(value: Float, points: [SIMD3<Float>], normals: [SIMD3<Float>]) {
        self.value = value
        self.points = points
        self.normals = normals
    }
}

/// One `BSBoneLODExtraData` entry: a bone and the distance it belongs to.
nonisolated public struct NIFBoneLOD: Equatable, Sendable {
    public let distance: UInt32
    public let boneName: String?

    public init(distance: UInt32, boneName: String?) {
        self.distance = distance
        self.boneName = boneName
    }
}

nonisolated extension NIFBlockDecoders {
    static let extraData: [String: Decode] = [
        "NiIntegerExtraData": extra { reader, _ in try .integer(reader.readUInt32()) },
        "BSXFlags": extra { reader, _ in try .flags(NIFBSXFlags(rawValue: reader.readUInt32())) },
        "NiFloatExtraData": extra { reader, _ in try .float(reader.readFloat32()) },
        "NiBooleanExtraData": extra { reader, _ in try .boolean(reader.readUInt8() != 0) },
        "NiStringsExtraData": extra { reader, _ in
            let count = try reader.readNIFCount(stride: 4, label: "string")
            return try .strings((0 ..< count).map { _ in try reader.readNIFSizedString() })
        },
        "NiBinaryExtraData": extra { reader, _ in
            let count = try reader.readNIFCount(stride: 1, label: "byte")
            return try .binary(reader.read(count: count))
        },
        "BSInvMarker": extra { reader, _ in
            let raw = try SIMD3<Float>(
                Float(reader.readUInt16()), Float(reader.readUInt16()), Float(reader.readUInt16())
            )
            return try .inventoryMarker(NIFInventoryMarker(
                rotation: raw / 1000, zoom: reader.readFloat32()
            ))
        },
        "BSBound": extra { reader, _ in
            try .bound(center: reader.readVector3(), halfExtents: reader.readVector3())
        },
        "BSDistantObjectLargeRefExtraData": extra { reader, _ in
            try .largeReference(reader.readUInt8() != 0)
        },
        "BSDecalPlacementVectorExtraData": extra { reader, _ in try decalPlacement(&reader) },
        "BSBoneLODExtraData": extra { reader, header in
            let count = try reader.readNIFCount(stride: 8, label: "bone LOD")
            return try .boneLOD((0 ..< count).map { _ in
                try NIFBoneLOD(
                    distance: reader.readUInt32(),
                    boneName: reader.readNIFString(header)
                )
            })
        }
    ]

    /// Every extra data block starts with its name.
    private static func extra(
        _ value: @escaping @Sendable (inout BinaryReader, NIFHeader) throws -> NIFExtraData.Value
    ) -> Decode {
        { reader, header in
            let name = try reader.readNIFString(header)
            return try NIFExtraData(name: name, value: value(&reader, header))
        }
    }

    /// An `NiFloatExtraData` value, then blocks of points with their normals.
    private static func decalPlacement(_ reader: inout BinaryReader) throws -> NIFExtraData.Value {
        let value = try reader.readFloat32()
        let blocks = try reader.readNIFShortCount(stride: 2, label: "decal vector block")
        var points: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        for _ in 0 ..< blocks {
            let count = try reader.readNIFShortCount(stride: 24, label: "decal vector")
            points += try (0 ..< count).map { _ in try reader.readVector3() }
            normals += try (0 ..< count).map { _ in try reader.readVector3() }
        }
        return .decalPlacement(NIFDecalPlacement(value: value, points: points, normals: normals))
    }
}

nonisolated extension NIFFile {
    /// The decoded extra data `block` names in its `NiObjectNET` list. A ref to a
    /// type with no decoder, or one that does not decode, is passed over.
    public func extraData(of block: Int) -> [NIFExtraData] {
        guard blocks.indices.contains(block) else { return [] }
        var reader = BinaryReader(blocks[block].data)
        guard let net = try? NIFObjectNET(reader: &reader, header: header) else { return [] }
        return net.extraDataRefs.compactMap { ref in
            guard ref >= 0, Int(ref) < blocks.count else { return nil }
            return try? NIFBlockDecoders.decode(blocks[Int(ref)], header: header) as? NIFExtraData
        }
    }

    /// The extra data of the first root, where the game reads `BSX` and `INV`.
    public var rootExtraData: [NIFExtraData] {
        roots.first.map { $0 >= 0 ? extraData(of: Int($0)) : [] } ?? []
    }

    /// The root's `BSXFlags`; empty when the model has none.
    public var bsxFlags: NIFBSXFlags {
        for case let .flags(flags) in rootExtraData.map(\.value) {
            return flags
        }
        return []
    }

    public var inventoryMarker: NIFInventoryMarker? {
        for case let .inventoryMarker(marker) in rootExtraData.map(\.value) {
            return marker
        }
        return nil
    }
}
