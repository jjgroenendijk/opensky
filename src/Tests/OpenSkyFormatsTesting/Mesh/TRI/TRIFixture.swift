// A three-vertex TRI with two named, scaled morphs, built in code. Layout:
// docs/formats/tri.md.

public import Foundation

public enum TRIFixture {
    public static func file() -> Data {
        var data = Data("FRTRI003".utf8)
        [3, 1, 0, 0, 0, 3, 1, 2, 0, 0, 0, 0, 0, 0]
            .forEach { data.appendInt32($0) }
        [
            SIMD3<Float>(0, 0, 0), SIMD3<Float>(1, 0, 0), SIMD3<Float>(0, 1, 0)
        ].forEach { vertex in
            data.appendFloat32(vertex.x)
            data.appendFloat32(vertex.y)
            data.appendFloat32(vertex.z)
        }
        [0, 1, 2].forEach { data.appendInt32($0) }
        for uv in [SIMD2<Float>(0, 0), SIMD2<Float>(1, 0), SIMD2<Float>(0, 1)] {
            data.appendFloat32(uv.x)
            data.appendFloat32(uv.y)
        }
        [0, 1, 2].forEach { data.appendInt32($0) }
        data.appendMorph(
            name: "Aah", scale: 0.5,
            deltas: [SIMD3(1, 0, 0), SIMD3(0, 2, 0), SIMD3(0, 0, -3)]
        )
        data.appendMorph(
            name: "Blink", scale: 0.25,
            deltas: [SIMD3(0, 0, 0), SIMD3(0, 0, 0), SIMD3(0, 4, 0)]
        )
        return data
    }
}

extension Data {
    fileprivate mutating func appendInt32(_ value: Int) {
        appendUInt32(UInt32(bitPattern: Int32(value)))
    }

    private mutating func appendInt16(_ value: Int16) {
        appendUInt16(UInt16(bitPattern: value))
    }

    fileprivate mutating func appendMorph(
        name: String,
        scale: Float,
        deltas: [SIMD3<Int16>]
    ) {
        let encoded = Data(name.utf8) + Data([0])
        appendUInt32(UInt32(encoded.count))
        append(encoded)
        appendFloat32(scale)
        for delta in deltas {
            appendInt16(delta.x)
            appendInt16(delta.y)
            appendInt16(delta.z)
        }
    }
}
