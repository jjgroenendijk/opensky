// Animation candidates: the HKX stored loose (parsed at load), and every
// frame's bone poses sampled once and stored raw, ten floats per track. The
// raw form makes a pose a table read instead of a spline evaluation.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyGameData
import OpenSkyRendering
import simd

extension AssetFormatComparison {
    static let floatsPerPose = 10

    func measureAnimation(_ entry: AssetSampleEntry) throws -> AssetMeasurement {
        let source = try files.contents(forPath: entry.path)
        let original = try originalRow(entry, sourceBytes: source.count) {
            let (data, read) = try Self.timed { try files.contents(forPath: entry.path) }
            return try parseAnimation(data, read: read)
        }
        let animations = try HKASplineCompressedAnimation.animations(in: HKXFile(data: source))
        let (sampled, sampleMS) = try Self.timed { try animations.map(Self.sampledPoses) }
        let packed = PackedBlobs(sampled.map { PackedBlobs.blob($0) })
        let shippedRows = cacheRows(
            candidate: "shipped", payload: source, paths: [.cpu], fidelity: .lossless
        ) { _, url, storage in
            let (data, read) = try Self.timed {
                try readCacheFile(url, storage, byteCount: source.count)
            }
            return try parseAnimation(data, read: read)
        }
        let readyRows = cacheRows(
            candidate: "ready", payload: packed.bytes, paths: [.cpu], fidelity: .lossless
        ) { _, url, storage in
            let (data, read) = try Self.timed {
                try readCacheFile(url, storage, byteCount: packed.bytes.count)
            }
            let (poses, decode) = try Self.timed {
                try packed.blobs(from: data).map { PackedBlobs.values($0, as: Float.self) }
            }
            return Sample(
                timing: AssetLoadTiming(readMS: read, decodeMS: decode, uploadMS: 0),
                memoryBytes: packed.bytes.count,
                mismatch: poses == sampled ? nil : "rebuilt poses differ"
            )
        }
        let frames = animations.map(\.frameCount).reduce(0, +)
        let tracks = animations.map(\.transformTrackCount).max() ?? 0
        let perPose = frames > 0 ? sampleMS * 1000 / Double(frames) : 0
        return AssetMeasurement(
            entry: entry,
            detail: "\(animations.count) clips, \(tracks) tracks, \(frames) frames; "
                + String(format: "%.1f us per pose from the spline", perPose),
            candidates: [original] + shippedRows + readyRows
        )
    }

    private func parseAnimation(_ data: Data, read: Double) throws -> Sample {
        let (animations, decode) = try Self.timed {
            try HKASplineCompressedAnimation.animations(in: HKXFile(data: data))
        }
        return Sample(
            timing: AssetLoadTiming(readMS: read, decodeMS: decode, uploadMS: 0),
            memoryBytes: animations.isEmpty ? 0 : data.count
        )
    }

    /// Every frame's local poses: translation, rotation, scale per track.
    static func sampledPoses(_ animation: HKASplineCompressedAnimation) throws -> [Float] {
        var floats: [Float] = []
        floats.reserveCapacity(
            animation.frameCount * animation.transformTrackCount * floatsPerPose
        )
        for frame in 0 ..< animation.frameCount {
            for pose in try animation.localTransforms(at: Float(frame) * animation.frameDuration) {
                let rotation = pose.rotation.vector
                floats += [
                    pose.translation.x, pose.translation.y, pose.translation.z,
                    rotation.x, rotation.y, rotation.z, rotation.w,
                    pose.scale.x, pose.scale.y, pose.scale.z
                ]
            }
        }
        return floats
    }
}
