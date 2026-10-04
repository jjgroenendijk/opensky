// Decoded spline-track values, standard de Boor evaluation, bounded cursor,
// and verified 40-bit quaternion unpacking. Format/source detail:
// docs/formats/hka-animation.md.

import Foundation
import simd

nonisolated public struct HKASplineTransformMask: Sendable {
    public let quantization: UInt8
    public let position: UInt8
    public let rotation: UInt8
    public let scale: UInt8
}

nonisolated public struct HKASplineVectorDescriptor: Sendable {
    public let typeMask: UInt8
    public let quantization: Int
    public let identity: Float
    public let trackIndex: Int
    public let component: String
}

nonisolated public enum HKASplineSubTrackType: Sendable {
    case identity
    case constant
    case spline
}

nonisolated public struct HKASplineBounds: Sendable {
    public let minimum: Float
    public let maximum: Float
}

nonisolated public struct HKASplineTransformTrack: Sendable {
    public let translation: HKASplineVectorTrack
    public let rotation: HKASplineQuaternionTrack
    public let scale: HKASplineVectorTrack
}

nonisolated public struct HKASplineVectorTrack: Sendable {
    public let constants: SIMD3<Float>
    public let types: [HKASplineSubTrackType]
    public let header: HKASplineHeader?
    public let controlPoints: [[Float]]

    public init(constants: SIMD3<Float>) {
        self.constants = constants
        types = [.constant, .constant, .constant]
        header = nil
        controlPoints = [[], [], []]
    }

    public init(
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

    public func value(at frame: Float) -> SIMD3<Float> {
        guard let header else { return constants }
        var value = constants
        for axis in 0 ..< 3 where types[axis] == .spline {
            value[axis] = header.value(at: frame, controlPoints: controlPoints[axis])
        }
        return value
    }
}

nonisolated public enum HKASplineQuaternionTrack: Sendable {
    case identity
    case constant(SIMD4<Float>)
    case spline(header: HKASplineHeader, controlPoints: [SIMD4<Float>])

    public func value(at frame: Float) -> SIMD4<Float> {
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

nonisolated public struct HKASplineHeader: Sendable {
    public let degree: Int
    public let knots: [UInt8]
    public let controlPointCount: Int

    public func value(at frame: Float, controlPoints: [Float]) -> Float {
        deBoor(at: frame, controlPoints: controlPoints) { (1 - $2) * $0 + $2 * $1 }
    }

    public func value(at frame: Float, controlPoints: [SIMD4<Float>]) -> SIMD4<Float> {
        deBoor(at: frame, controlPoints: controlPoints) { (1 - $2) * $0 + $2 * $1 }
    }

    /// De Boor's algorithm. `blend(a, b, alpha)` returns `(1 - alpha) * a + alpha * b`.
    private func deBoor<Point>(
        at frame: Float,
        controlPoints: [Point],
        blend: (Point, Point, Float) -> Point
    ) -> Point {
        let span = knotSpan(for: frame)
        // Stack scratch, not an Array: this runs per sub-track per sample.
        return withUnsafeTemporaryAllocation(of: Point.self, capacity: degree + 1) { points in
            for index in 0 ... degree {
                points.initializeElement(at: index, to: controlPoints[span - degree + index])
            }
            defer { _ = points.deinitialize() }
            for level in 1 ... degree {
                for index in stride(from: degree, through: level, by: -1) {
                    let knotIndex = span - degree + index
                    let denominator = Float(
                        Int(knots[knotIndex + degree - level + 1]) - Int(knots[knotIndex])
                    )
                    let alpha = denominator == 0
                        ? 0
                        : (frame - Float(knots[knotIndex])) / denominator
                    points[index] = blend(points[index - 1], points[index], alpha)
                }
            }
            return points[degree]
        }
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

nonisolated public struct HKASplineCursor: Sendable {
    public let data: Data
    public let blockIndex: Int
    public var offset: Int
    public let limit: Int

    public mutating func readUInt8() throws -> UInt8 {
        try require(1)
        defer { offset += 1 }
        return data[offset]
    }

    public mutating func readUInt16() throws -> UInt16 {
        let low = try UInt16(readUInt8())
        return try low | UInt16(readUInt8()) << 8
    }

    public mutating func readUInt32() throws -> UInt32 {
        let low = try UInt32(readUInt16())
        return try low | UInt32(readUInt16()) << 16
    }

    public mutating func readFloat() throws -> Float {
        try Float(bitPattern: readUInt32())
    }

    public mutating func readFiniteFloat(trackIndex: Int, component: String) throws -> Float {
        let value = try readFloat()
        guard value.isFinite else {
            throw HKASplineAnimationError.invalidSpline(
                trackIndex: trackIndex, component: component, reason: "non-finite float"
            )
        }
        return value
    }

    public mutating func readSplineHeader(
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
    public mutating func readQuaternion40() throws -> SIMD4<Float> {
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

    public mutating func skip(_ count: Int) throws {
        try require(count)
        offset += count
    }

    public mutating func align(to alignment: Int) throws {
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
