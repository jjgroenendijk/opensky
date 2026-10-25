// The two transform structs Havok embeds in physics and mapping classes.
// Byte map: docs/formats/hkx-physics.md.

import Foundation
import simd

/// `hkTransform`, 64 bytes: three rotation columns, then the translation.
nonisolated public struct HKTransform: Equatable, Sendable {
    public let rotation: simd_float3x3
    public let translation: SIMD3<Float>

    public init(rotation: simd_float3x3, translation: SIMD3<Float>) {
        self.rotation = rotation
        self.translation = translation
    }

    public static func decode(
        _ cursor: inout HKXObjectCursor, at offset: Int, named member: String
    ) -> HKTransform {
        var columns: [SIMD3<Float>] = []
        for index in 0 ..< 4 {
            let field = HKXField(offset + index * 16, "\(member)[\(index)]")
            let value = cursor.vector4(at: field) ?? SIMD4()
            columns.append(SIMD3(value.x, value.y, value.z))
        }
        return HKTransform(
            rotation: simd_float3x3(columns[0], columns[1], columns[2]),
            translation: columns[3]
        )
    }

    /// True when every lane is finite and the rotation keeps lengths.
    public var isRigid: Bool {
        let product = rotation.transpose * rotation
        let columns = [product.columns.0, product.columns.1, product.columns.2]
        let identity = [SIMD3<Float>(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1)]
        return translation.allFinite && zip(columns, identity).allSatisfy {
            simd_length($0 - $1) < 1e-3
        }
    }
}

/// `hkQsTransform`, 48 bytes: translation, rotation quaternion, scale.
nonisolated public struct HKQsTransform: Equatable, Sendable {
    public let translation: SIMD3<Float>
    public let rotation: simd_quatf
    public let scale: SIMD3<Float>

    public static let stride = 48

    public init(translation: SIMD3<Float>, rotation: simd_quatf, scale: SIMD3<Float>) {
        self.translation = translation
        self.rotation = rotation
        self.scale = scale
    }

    public static func decode(
        _ cursor: inout HKXObjectCursor, at offset: Int, named member: String
    ) -> HKQsTransform {
        let translation = cursor.vector4(at: HKXField(offset, "\(member).m_translation"))
        let rotation = cursor.vector4(at: HKXField(offset + 16, "\(member).m_rotation"))
        let scale = cursor.vector4(at: HKXField(offset + 32, "\(member).m_scale"))
        let quad = rotation ?? SIMD4(0, 0, 0, 1)
        return HKQsTransform(
            translation: (translation ?? SIMD4()).xyz,
            rotation: simd_quatf(ix: quad.x, iy: quad.y, iz: quad.z, r: quad.w),
            scale: (scale ?? SIMD4(1, 1, 1, 0)).xyz
        )
    }

    public static func == (lhs: HKQsTransform, rhs: HKQsTransform) -> Bool {
        lhs.translation == rhs.translation && lhs.rotation.vector == rhs.rotation.vector
            && lhs.scale == rhs.scale
    }

    /// True when every lane is finite and the rotation is a unit quaternion.
    public var isValid: Bool {
        translation.allFinite && scale.allFinite
            && abs(simd_length(rotation.vector) - 1) < 1e-3
    }
}

nonisolated extension SIMD4<Float> {
    var xyz: SIMD3<Float> {
        SIMD3(x, y, z)
    }
}

nonisolated extension SIMD3<Float> {
    var allFinite: Bool {
        x.isFinite && y.isFinite && z.isFinite
    }
}
