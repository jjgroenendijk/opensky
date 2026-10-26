// The path an `NiPathInterpolator` moves a node along: `NiPosData` points, and
// `NiFloatData` keys that give the fraction of the path at each time.
// Layout: docs/formats/nif-controllers.md#interpolators.

import Foundation
import OpenSkyFormatsCore
import simd

nonisolated public struct NIFPath: Equatable, Sendable {
    public let points: [NIFKey<SIMD3<Float>>]
    /// Fraction of the path, 0 to 1, by time in seconds.
    public let percent: [NIFKey<Float>]
    /// Equal fractions cover equal distances, not equal spans of point time.
    public let hasConstantVelocity: Bool
    /// The flags, bank, smoothing, and follow axis.
    public let interpolator: NIFPathInterpolator

    /// The path of the `NiPathInterpolator` at `ref`; nil for another block type.
    init?(interpolatorRef ref: Int32, file: NIFFile) throws {
        guard ref >= 0, Int(ref) < file.blocks.count else { return nil }
        let block = file.blocks[Int(ref)]
        guard block.typeName == NIFPathInterpolator.typeName else { return nil }
        var reader = BinaryReader(block.data)
        let path = try NIFPathInterpolator(reader: &reader)
        points = try Self.keys(path.pathDataRef, "NiPosData", file) { try $0.readVector3() }
        percent = try Self.keys(path.percentDataRef, "NiFloatData", file) { try $0.readFloat32() }
        hasConstantVelocity = path.hasConstantVelocity
        interpolator = path
    }

    /// The fraction of the path, 0 to 1, at `time` seconds.
    public func fraction(at time: Float) -> Float {
        simd_clamp(NIFKeySampler.float(percent, at: time) ?? 0, 0, 1)
    }

    /// The point on the path at `time` seconds; nil without points.
    public func position(at time: Float) -> SIMD3<Float>? {
        position(atFraction: fraction(at: time))
    }

    /// The point a fraction of the way along the path; nil without points.
    public func position(atFraction fraction: Float) -> SIMD3<Float>? {
        guard let first = points.first, let last = points.last else { return nil }
        let fraction = simd_clamp(fraction, 0, 1)
        guard hasConstantVelocity, points.count > 1 else {
            return NIFKeySampler.vector(
                points,
                at: first.time + (last.time - first.time) * fraction
            )
        }
        let lengths = zip(points, points.dropFirst()).map { simd_distance($0.value, $1.value) }
        var remaining = lengths.reduce(0, +) * fraction
        for (index, length) in lengths.enumerated() {
            guard remaining > length, index < lengths.count - 1 else {
                let step = length > 0 ? remaining / length : 0
                return simd_mix(
                    points[index].value,
                    points[index + 1].value,
                    SIMD3(repeating: step)
                )
            }
            remaining -= length
        }
        return last.value
    }

    private static func keys<Value>(
        _ ref: Int32,
        _ type: String,
        _ file: NIFFile,
        value: (inout BinaryReader) throws -> Value
    ) throws -> [NIFKey<Value>] {
        guard ref >= 0, Int(ref) < file.blocks.count else { return [] }
        let block = file.blocks[Int(ref)]
        guard block.typeName == type else {
            throw NIFError.malformed("path interpolator data is \(block.typeName), not \(type)")
        }
        var reader = BinaryReader(block.data)
        return try NIFTransformData.keyGroup(&reader, value: value)
    }
}

/// A `BSFrustumFOVController`'s horizontal field of view keys, degrees.
nonisolated public struct NIFFieldOfViewTrack: Equatable, Sendable {
    public let timing: ControllerTiming
    public let degrees: [NIFKey<Float>]

    /// The first field of view controller on the chain from `ref`; nil when none.
    init?(controllerRef ref: Int32, file: NIFFile) throws {
        var next = ref
        var visited: Set<Int32> = []
        while next >= 0, Int(next) < file.blocks.count, visited.insert(next).inserted {
            let block = file.blocks[Int(next)]
            var reader = BinaryReader(block.data)
            let controller = try NIFTimeController(reader: &reader)
            if block.typeName == NIFPlainController.Kind.frustumFieldOfView.rawValue {
                timing = controller.timing
                degrees = try NIFParticleControllerDecoder.floatKeys(
                    reader.readNIFRef(),
                    file: file
                )
                return
            }
            next = controller.nextControllerRef
        }
        return nil
    }

    /// Radians at `time` seconds of the camera's own clock; nil without keys.
    public func horizontalFieldOfView(at time: Float) -> Float? {
        NIFKeySampler.float(degrees, at: timing.controllerTime(at: time)).map { $0 * .pi / 180 }
    }
}
