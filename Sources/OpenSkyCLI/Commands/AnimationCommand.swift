// `animation <hkx-key>`: decode hkaSplineCompressedAnimation tracks (todo
// 6.3), then sample every stored frame through the shared engine decoder.
// Any malformed, NaN/inf, or unbounded transform exits 1.

import Foundation
import simd

enum AnimationCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let key = try scanner.positional("hkx-key")
        try scanner.finish()
        let file: HKXFile
        let animations: [HKASplineCompressedAnimation]
        let bindings: [HKAAnimationBinding]
        do {
            let data = try context.makeFileSystem().contents(forPath: key)
            file = try HKXFile(data: data)
            animations = try HKASplineCompressedAnimation.animations(in: file)
            bindings = try HKAAnimationBinding.bindings(in: file)
        } catch {
            throw CLIError.failure("cannot decode \(key): \(String(describing: error))")
        }
        guard !animations.isEmpty else {
            throw CLIError.failure("no hkaSplineCompressedAnimation in \(key)")
        }
        print("[INFO] \(key): \(animations.count) hkaSplineCompressedAnimation object(s)")
        for (index, animation) in animations.enumerated() {
            let target = HKXPointerTarget(
                sectionIndex: animation.objectSectionIndex,
                dataOffset: animation.objectDataOffset
            )
            guard let binding = bindings.first(where: { $0.animationTarget == target }) else {
                throw CLIError.failure("animation \(index) has no hkaAnimationBinding")
            }
            try validate(index: index, animation: animation, binding: binding)
        }
    }

    private static func validate(
        index: Int,
        animation: HKASplineCompressedAnimation,
        binding: HKAAnimationBinding
    ) throws {
        var translationMaximum: Float = 0
        var scaleMaximum: Float = 0
        var quaternionNormMinimum = Float.greatestFiniteMagnitude
        var quaternionNormMaximum: Float = 0
        do {
            for frame in 0 ..< animation.frameCount {
                let time = frame == animation.frameCount - 1
                    ? animation.duration
                    : Float(frame) * animation.frameDuration
                let samples = try animation.boneLocalTransforms(at: time, binding: binding)
                for sample in samples {
                    let pose = sample.pose
                    translationMaximum = max(translationMaximum, maxAbs(pose.translation))
                    scaleMaximum = max(scaleMaximum, maxAbs(pose.scale))
                    let norm = simd_length(pose.rotation.vector)
                    quaternionNormMinimum = min(quaternionNormMinimum, norm)
                    quaternionNormMaximum = max(quaternionNormMaximum, norm)
                }
            }
        } catch {
            throw CLIError.failure(
                "animation \(index) sample failed: \(String(describing: error))"
            )
        }
        print("animation \(index): \(animation.frameCount) frames x "
            + "\(animation.transformTrackCount) tracks, \(animation.blockCount) blocks, "
            + "duration \(String(format: "%.6f", animation.duration)) s")
        let mapping = binding.transformTrackToBoneIndices.isEmpty ? "identity" : "explicit"
        print("  bone mapping \(mapping): \(animation.transformTrackCount) samples, "
            + "skeleton \(binding.originalSkeletonName ?? "<unnamed>")")
        print("  full duration finite + bounded: translation max "
            + "\(String(format: "%.6f", translationMaximum)), scale max "
            + "\(String(format: "%.6f", scaleMaximum)), quaternion norm "
            + "\(String(format: "%.6f", quaternionNormMinimum))..."
            + String(format: "%.6f", quaternionNormMaximum))
    }

    private static func maxAbs(_ value: SIMD3<Float>) -> Float {
        max(abs(value.x), abs(value.y), abs(value.z))
    }
}
