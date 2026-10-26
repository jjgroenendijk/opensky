// Interpolators beyond the keyed float, bool, point, and transform ones: the
// blend interpolators a controller manager feeds, the path interpolator, and
// the look-at interpolator. Layout: docs/formats/nif-controllers.md#interpolators.

import Foundation
import OpenSkyFormatsCore
import simd

/// `NiBlendFloatInterpolator`, `NiBlendBoolInterpolator`, or `NiBlendPoint3Interpolator`.
/// A controller a manager drives points at one; the playing sequence fills it.
nonisolated public struct NIFBlendInterpolator: Equatable, Sendable {
    public static let floatType = "NiBlendFloatInterpolator"
    public static let boolType = "NiBlendBoolInterpolator"
    public static let point3Type = "NiBlendPoint3Interpolator"

    public enum Value: Equatable, Sendable {
        /// Nil when the file stores `#INV_FLT#`, "not set".
        case float(Float?)
        /// Nil when the file stores 2, "not set".
        case bool(Bool?)
        case point3(SIMD3<Float>?)
    }

    public struct Item: Equatable, Sendable {
        public let interpolatorRef: Int32
        public let weight: Float
        public let normalizedWeight: Float
        public let priority: UInt8
        public let easeSpinner: Float
    }

    /// nif.xml `InterpBlendFlags`: bit 0 manager controlled, bit 1 highest weight only.
    public let flags: UInt8
    public let weightThreshold: Float
    /// Empty for a manager-controlled blend, which stores no items.
    public let items: [Item]
    public let value: Value

    public init(reader: inout BinaryReader, typeName: String) throws {
        flags = try reader.readUInt8()
        let size = try Int(reader.readUInt8())
        weightThreshold = try reader.readFloat32()
        var items: [Item] = []
        if flags & 1 == 0 {
            reader.skip(4 + 4 * 4) // counts, priorities, single time, weight sums, spinner
            _ = try reader.checkNIFCount(size, stride: 17, label: "blend item")
            items = try (0 ..< size).map { _ in
                try Item(
                    interpolatorRef: reader.readNIFRef(), weight: reader.readFloat32(),
                    normalizedWeight: reader.readFloat32(), priority: reader.readUInt8(),
                    easeSpinner: reader.readFloat32()
                )
            }
        }
        self.items = items
        value = switch typeName {
        case Self.boolType:
            try .bool(Self.bool(reader.readUInt8()))
        case Self.point3Type:
            try .point3(Self.point(reader.readVector3()))
        default:
            try .float(Self.float(reader.readFloat32()))
        }
    }

    static func float(_ value: Float) -> Float? {
        value.isFinite && value != NIFParticleControllerDecoder.invalidFloat ? value : nil
    }

    static func bool(_ value: UInt8) -> Bool? {
        value > 1 ? nil : value == 1
    }

    static func point(_ value: SIMD3<Float>) -> SIMD3<Float>? {
        float(value.x) == nil ? nil : value
    }
}

/// `NiPathInterpolator`: moves an object along a spline of `NiPosData` keys, by the
/// fraction of the path its `NiFloatData` keys give at each time.
nonisolated public struct NIFPathInterpolator: Equatable, Sendable {
    public static let typeName = "NiPathInterpolator"

    /// nif.xml `PathFlags`.
    public let flags: UInt16
    public let bankDirection: Int32
    public let maximumBankAngle: Float
    public let smoothing: Float
    /// 0, 1, or 2: the object axis that points along the path when it follows.
    public let followAxis: Int16
    public let pathDataRef: Int32
    public let percentDataRef: Int32

    public init(reader: inout BinaryReader) throws {
        flags = try reader.readUInt16()
        bankDirection = try Int32(bitPattern: reader.readUInt32())
        maximumBankAngle = try reader.readFloat32()
        smoothing = try reader.readFloat32()
        followAxis = try Int16(bitPattern: reader.readUInt16())
        pathDataRef = try reader.readNIFRef()
        percentDataRef = try reader.readNIFRef()
    }

    /// Flag bit 4: equal distances take equal times, whatever the key spacing.
    public var hasConstantVelocity: Bool {
        flags & 0x10 != 0
    }

    /// Flag bit 5: the object turns to face along the path.
    public var follows: Bool {
        flags & 0x20 != 0
    }

    /// Flag bit 3: a following object tilts into a turn.
    public var banks: Bool {
        flags & 0x8 != 0
    }

    /// Flag bit 6: the follow axis points backwards along the path.
    public var flips: Bool {
        flags & 0x40 != 0
    }
}

/// `NiLookAtInterpolator`: turns an object to face another node.
nonisolated public struct NIFLookAtInterpolator: Equatable, Sendable {
    public static let typeName = "NiLookAtInterpolator"

    /// nif.xml `LookAtFlags`: bit 0 flip, bit 1 Y axis, bit 2 Z axis (else X).
    public let flags: UInt16
    public let lookAtRef: Int32
    public let lookAtName: String?
    public let translation: SIMD3<Float>?
    public let rotation: simd_quatf?
    public let scale: Float?
    public let translationInterpolatorRef: Int32
    public let rollInterpolatorRef: Int32
    public let scaleInterpolatorRef: Int32

    public init(reader: inout BinaryReader, header: NIFHeader) throws {
        flags = try reader.readUInt16()
        lookAtRef = try reader.readNIFRef()
        lookAtName = try reader.readNIFString(header)
        translation = try NIFBlendInterpolator.point(reader.readVector3())
        let rotation = try NIFTransformData.readQuaternion(&reader)
        self.rotation = NIFBlendInterpolator.float(rotation.real) == nil ? nil : rotation
        scale = try NIFBlendInterpolator.float(reader.readFloat32())
        translationInterpolatorRef = try reader.readNIFRef()
        rollInterpolatorRef = try reader.readNIFRef()
        scaleInterpolatorRef = try reader.readNIFRef()
    }

    /// The object axis that points at the target.
    public var lookAxis: SIMD3<Float> {
        let axis: SIMD3<Float> = flags & 0x2 != 0 ? SIMD3(0, 1, 0)
            : flags & 0x4 != 0 ? SIMD3(0, 0, 1) : SIMD3(1, 0, 0)
        return flags & 0x1 != 0 ? -axis : axis
    }
}

nonisolated extension NIFBlockDecoders {
    static let interpolators: [String: Decode] = [
        NIFBlendInterpolator.floatType: { reader, _ in
            try NIFBlendInterpolator(reader: &reader, typeName: NIFBlendInterpolator.floatType)
        },
        NIFBlendInterpolator.boolType: { reader, _ in
            try NIFBlendInterpolator(reader: &reader, typeName: NIFBlendInterpolator.boolType)
        },
        NIFBlendInterpolator.point3Type: { reader, _ in
            try NIFBlendInterpolator(reader: &reader, typeName: NIFBlendInterpolator.point3Type)
        },
        NIFPathInterpolator.typeName: { reader, _ in try NIFPathInterpolator(reader: &reader) },
        NIFLookAtInterpolator.typeName: { try NIFLookAtInterpolator(reader: &$0, header: $1) }
    ]
}
