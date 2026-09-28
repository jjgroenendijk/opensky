// Decoded spline-track values, standard de Boor evaluation, bounded cursor,
// and verified 40-bit quaternion unpacking. Format/source detail:
// docs/formats/hka-animation.md.

import Foundation
import simd

nonisolated package struct HKASplineTransformMask {
    package let quantization: UInt8
    package let position: UInt8
    package let rotation: UInt8
    package let scale: UInt8
}

nonisolated package struct HKASplineVectorDescriptor {
    package let typeMask: UInt8
    package let quantization: Int
    package let identity: Float
    package let trackIndex: Int
    package let component: String
}

nonisolated package enum HKASplineSubTrackType {
    case identity
    case constant
    case spline
}

nonisolated package struct HKASplineBounds {
    package let minimum: Float
    package let maximum: Float
}

nonisolated package struct HKASplineTransformTrack {
    package let translation: HKASplineVectorTrack
    package let rotation: HKASplineQuaternionTrack
    package let scale: HKASplineVectorTrack
}

nonisolated package struct HKASplineVectorTrack {
    package let constants: SIMD3<Float>
    package let types: [HKASplineSubTrackType]
    package let header: HKASplineHeader?
    package let controlPoints: [[Float]]

    package init(constants: SIMD3<Float>) {
        self.constants = constants
        types = [.constant, .constant, .constant]
        header = nil
        controlPoints = [[], [], []]
    }

    package init(
        constants: SIMD3<Float>,
        types: [HKASplineSubTrackType],
        header: HKASplineHeader,
        controlPoints: [[Float]]
    ) {
        self.constants = constants
        self.types = types
        self.header = header
        self.controlPoints = controlPoints
    }

    package func value(at frame: Float) -> SIMD3<Float> {
        guard let header else { return constants }
        var value = constants
        for axis in 0 ..< 3 where types[axis] == .spline {
            value[axis] = header.value(at: frame, controlPoints: controlPoints[axis])
        }
        return value
    }
}

nonisolated package enum HKASplineQuaternionTrack {
    case identity
    case constant(SIMD4<Float>)
    case spline(header: HKASplineHeader, controlPoints: [SIMD4<Float>])

    package func value(at frame: Float) -> SIMD4<Float> {
        switch self {
        case .identity:
            SIMD4(0, 0, 0, 1)
        case let .constant(value):
            value
        case let .spline(header, controlPoints):
            header.value(at: frame, controlPoints: controlPoints)
        }
    }
}

nonisolated package struct HKASplineHeader {
    package let degree: Int
    package let knots: [UInt8]
    package let controlPointCount: Int

    package func value(at frame: Float, controlPoints: [Float]) -> Float {
        let span = knotSpan(for: frame)
        var points = (0 ... degree).map { controlPoints[span - degree + $0] }
        for level in 1 ... degree {
            for index in stride(from: degree, through: level, by: -1) {
                let knotIndex = span - degree + index
                let denominator = Float(
                    Int(knots[knotIndex + degree - level + 1]) - Int(knots[knotIndex])
                )
                let alpha = denominator == 0
                    ? 0
                    : (frame - Float(knots[knotIndex])) / denominator
                points[index] = (1 - alpha) * points[index - 1] + alpha * points[index]
            }
        }
        return points[degree]
    }

    package func value(at frame: Float, controlPoints: [SIMD4<Float>]) -> SIMD4<Float> {
        let span = knotSpan(for: frame)
        var points = (0 ... degree).map { controlPoints[span - degree + $0] }
        for level in 1 ... degree {
            for index in stride(from: degree, through: level, by: -1) {
                let knotIndex = span - degree + index
                let denominator = Float(
                    Int(knots[knotIndex + degree - level + 1]) - Int(knots[knotIndex])
                )
                let alpha = denominator == 0
                    ? 0
                    : (frame - Float(knots[knotIndex])) / denominator
                points[index] = (1 - alpha) * points[index - 1] + alpha * points[index]
            }
        }
        return points[degree]
    }

    private func knotSpan(for frame: Float) -> Int {
        if frame >= Float(knots[controlPointCount]) {
            return controlPointCount - 1
        }
        var low = degree
        var high = controlPointCount
        var middle = (low + high) / 2
        while frame < Float(knots[middle]) || frame >= Float(knots[middle + 1]) {
            if frame < Float(knots[middle]) {
                high = middle
            } else {
                low = middle
            }
            middle = (low + high) / 2
        }
        return middle
    }
}

nonisolated package struct HKASplineCursor {
    package let data: Data
    package let blockIndex: Int
    package var offset: Int
    package let limit: Int

    package mutating func readUInt8() throws -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return data[offset]
    }

    package mutating func readUInt16() throws -> UInt16 {
        let low = try UInt16(readUInt8())
        return try low | UInt16(readUInt8()) << 8
    }

    package mutating func readUInt32() throws -> UInt32 {
        let low = try UInt32(readUInt16())
        return try low | UInt32(readUInt16()) << 16
    }

    package mutating func readFloat() throws -> Float {
        try Float(bitPattern: readUInt32())
    }

    package mutating func readFiniteFloat(trackIndex: Int, component: String) throws -> Float {
        let value = try readFloat()
        guard value.isFinite else {
            throw HKASplineAnimationError.invalidSpline(
                trackIndex: trackIndex, component: component, reason: "non-finite float"
            )
        }
        return value
    }

    package mutating func readSplineHeader(
        trackIndex: Int,
        component: String
    ) throws -> HKASplineHeader {
        let storedItemCount = try Int(readUInt16())
        let degree = try Int(readUInt8())
        let controlPointCount = storedItemCount + 1
        guard degree >= 1, degree <= 4, controlPointCount > degree else {
            throw HKASplineAnimationError.invalidSpline(
                trackIndex: trackIndex,
                component: component,
                reason: "degree \(degree), control points \(controlPointCount)"
            )
        }
        var knots: [UInt8] = []
        knots.reserveCapacity(storedItemCount + degree + 2)
        for _ in 0 ..< storedItemCount + degree + 2 {
            try knots.append(readUInt8())
        }
        guard zip(knots, knots.dropFirst()).allSatisfy({ $0 <= $1 }) else {
            throw HKASplineAnimationError.invalidSpline(
                trackIndex: trackIndex, component: component, reason: "descending knots"
            )
        }
        return HKASplineHeader(
            degree: degree, knots: knots, controlPointCount: controlPointCount
        )
    }

    /// Havok 40-bit quaternion: three signed 12-bit components scaled to
    /// [-1/sqrt(2), +1/sqrt(2)], 2-bit omitted-largest lane, 1-bit sign.
    package mutating func readQuaternion40() throws -> SIMD4<Float> {
        var bits: UInt64 = 0
        for byteIndex in 0 ..< 5 {
            try bits |= UInt64(readUInt8()) << UInt64(byteIndex * 8)
        }
        let scale: Float = 0.000_345_436
        let stored = [
            Float(Int(bits & 0xFFF) - 2047) * scale,
            Float(Int((bits >> 12) & 0xFFF) - 2047) * scale,
            Float(Int((bits >> 24) & 0xFFF) - 2047) * scale
        ]
        let squareSum = stored.reduce(0) { $0 + $1 * $1 }
        let omitted = sqrt(max(0, 1 - squareSum)) * ((bits >> 38) & 1 == 0 ? 1 : -1)
        let omittedIndex = Int((bits >> 36) & 0x03)
        var output = SIMD4<Float>.zero
        var storedIndex = 0
        for axis in 0 ..< 4 {
            if axis == omittedIndex {
                output[axis] = omitted
            } else {
                output[axis] = stored[storedIndex]
                storedIndex += 1
            }
        }
        return output
    }

    package mutating func skip(_ count: Int) throws {
        try require(count)
        offset += count
    }

    package mutating func align(to alignment: Int) throws {
        let aligned = (offset + alignment - 1) & ~(alignment - 1)
        try skip(aligned - offset)
    }

    private func require(_ count: Int) throws {
        guard count >= 0, offset >= 0, offset <= limit - count else {
            throw HKASplineAnimationError.blockOutOfBounds(
                blockIndex: blockIndex, offset: offset, limit: limit
            )
        }
    }
}
