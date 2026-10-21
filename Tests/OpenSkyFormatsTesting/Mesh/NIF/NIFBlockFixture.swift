// Synthetic payloads for the whole-block decoders: extra data, node kinds,
// controllers, interpolators, legacy geometry, and the sky shader. Layouts follow
// nif.xml; see docs/formats/nif.md. No game bytes are fixtures.

import Foundation
import simd

public enum NIFBlockFixture: Sendable {
    /// nif.xml `NiTimeController`. Flags 0x8 is active, 0x20 manager controlled.
    public static func timeController(
        next: Int32 = -1,
        flags: UInt16 = 0x8,
        start: Float = 0,
        stop: Float = 1,
        target: Int32 = 0
    ) -> Data {
        var out = Data()
        out.appendRef(next)
        out.appendUInt16(flags)
        for value in [Float(1), 0, start, stop] {
            out.appendFloat32(value)
        }
        out.appendRef(target)
        return out
    }

    /// `NiSingleInterpController`: a time controller and its interpolator ref.
    public static func interpolatedController(
        next: Int32 = -1,
        flags: UInt16 = 0x8,
        stop: Float = 1,
        interpolator: Int32
    ) -> Data {
        var out = timeController(next: next, flags: flags, stop: stop)
        out.appendRef(interpolator)
        return out
    }

    /// An extra data block: its name index, then `value`.
    public static func extraData(nameIndex: UInt32 = 0xFFFF_FFFF, _ value: Data) -> Data {
        var out = Data()
        out.appendUInt32(nameIndex)
        out.append(value)
        return out
    }

    public static func uint32(_ value: UInt32) -> Data {
        var out = Data()
        out.appendUInt32(value)
        return out
    }

    public static func floats(_ values: [Float]) -> Data {
        var out = Data()
        for value in values {
            out.appendFloat32(value)
        }
        return out
    }

    /// `BSInvMarker`: three uint16 thousandths of a radian and a zoom.
    public static func inventoryMarker(rotation: SIMD3<UInt16>, zoom: Float) -> Data {
        var out = Data()
        out.appendUInt16(rotation.x)
        out.appendUInt16(rotation.y)
        out.appendUInt16(rotation.z)
        out.appendFloat32(zoom)
        return out
    }

    /// `NiFloatKeyGroup` or `NiPosData` with linear keys.
    public static func keyGroup(_ keys: [(Float, [Float])]) -> Data {
        var out = Data()
        out.appendUInt32(UInt32(keys.count))
        if !keys.isEmpty {
            out.appendUInt32(1)
        }
        for (time, values) in keys {
            out.appendFloat32(time)
            out.append(floats(values))
        }
        return out
    }

    /// `NiPathInterpolator`. Flags 0x10 is constant velocity.
    public static func pathInterpolator(
        flags: UInt16,
        pathData: Int32,
        percentData: Int32
    ) -> Data {
        var out = Data()
        out.appendUInt16(flags)
        out.appendUInt32(0) // bank direction
        out.append(floats([0, 0]))
        out.appendUInt16(0) // follow axis
        out.appendRef(pathData)
        out.appendRef(percentData)
        return out
    }

    /// `BSSkyShaderProperty` with no extra data and no controller.
    public static func skyShader(texture: String, skyObject: UInt32) -> Data {
        var out = NIFFixture.objectNETPrefix()
        out.appendUInt32(0)
        out.appendUInt32(0)
        out.append(floats([0, 0, 1, 1]))
        out.append(NIFFixture.sizedString(texture))
        out.appendUInt32(skyObject)
        return out
    }

    /// `NiTriShape` with no materials; `lodSizes` makes it a `BSLODTriShape`.
    public static func legacyTriShape(
        prefix: Data = NIFFixture.avObjectPrefix(),
        dataRef: Int32,
        shaderRef: Int32 = -1,
        lodSizes: [UInt32] = []
    ) -> Data {
        var out = prefix
        out.appendRef(dataRef)
        out.appendRef(-1) // skin
        out.appendUInt32(0) // materials
        out.appendUInt32(0) // active material
        out.append(0)
        out.appendRef(shaderRef)
        out.appendRef(-1) // alpha
        for size in lodSizes {
            out.appendUInt32(size)
        }
        return out
    }

    /// `NiTriShapeData` with positions, one UV set, and one triangle list.
    public static func triShapeData(
        positions: [SIMD3<Float>],
        uvs: [SIMD2<Float>],
        triangles: [UInt16]
    ) -> Data {
        var out = Data()
        out.appendUInt32(0) // group ID
        out.appendUInt16(UInt16(positions.count))
        out.append(contentsOf: [0, 0, 1])
        positions.forEach { out.appendVector3($0) }
        out.appendUInt16(1) // one UV set
        out.appendUInt32(0) // material CRC
        out.append(0) // no normals
        out.append(floats([0, 0, 0, 1])) // bounding sphere
        out.append(0) // no colours
        uvs.forEach { out.append(floats([$0.x, $0.y])) }
        out.appendUInt16(0) // consistency
        out.appendRef(-1) // additional data
        out.appendUInt16(UInt16(triangles.count / 3))
        out.appendUInt32(UInt32(triangles.count))
        out.append(1)
        triangles.forEach { out.appendUInt16($0) }
        out.appendUInt16(0) // match groups
        return out
    }

    /// `BSValueNode`: a node, then the `ADDN` index and flags.
    public static func valueNode(
        prefix: Data = NIFFixture.avObjectPrefix(),
        value: UInt32
    ) -> Data {
        var out = NIFFixture.niNode(prefix: prefix)
        out.appendUInt32(value)
        out.append(0)
        return out
    }
}
