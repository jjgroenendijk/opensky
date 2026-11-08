import OpenSkyBehavior
public import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyRenderCore
import OpenSkyRendering
import OpenSkyRenderResources
import simd
import Synchronization

/// The latest pose the behavior graph produced. An unchanged `revision` means no step ran
/// since the last frame, so the consumer skips the compose-and-upload path.
nonisolated public final class PlayerPoseBuffer: Sendable {
    nonisolated public struct Snapshot: Sendable {
        public var bones: [HKABonePose] = []
        public var revision = 0
        /// Bones another graph drives, by rig index, such as a worn tail's.
        var overlay: [Int: HKABonePose] = [:]
    }

    private let state = Mutex(Snapshot())

    public init() {}

    public var snapshot: Snapshot {
        state.withLock { $0 }
    }

    public var bones: [HKABonePose] {
        state.withLock { $0.bones }
    }

    public var revision: Int {
        state.withLock { $0.revision }
    }

    public func publish(_ bones: [HKABonePose]) {
        state.withLock {
            $0.bones = Self.applying($0.overlay, to: bones)
            $0.revision &+= 1
        }
    }

    /// Bones a sub-graph drives. Every later pose keeps them until the overlay changes.
    public func setOverlay(_ overlay: [Int: HKABonePose]) {
        state.withLock {
            guard !(overlay.isEmpty && $0.overlay.isEmpty) else { return }
            $0.overlay = overlay
            $0.bones = Self.applying(overlay, to: $0.bones)
            $0.revision &+= 1
        }
    }

    private static func applying(
        _ overlay: [Int: HKABonePose], to bones: [HKABonePose]
    ) -> [HKABonePose] {
        var bones = bones
        for (index, pose) in overlay where bones.indices.contains(index) {
            bones[index] = pose
        }
        return bones
    }

    /// Drops the pose, so a body attached after a reset composes from the
    /// reference pose rather than from wherever the player last stood.
    public func clear() {
        state.withLock {
            $0.bones = []
            $0.revision &+= 1
        }
    }
}
