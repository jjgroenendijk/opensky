// Animation the renderer steps once per frame. The world owns the playback
// objects; the scene holds them so a cell's animations leave with its scene.

import OpenSkyFormatsCore
import simd

/// RenderScene stores these references. Removing a resident CellScene removes
/// its playback objects; decoded immutable clip assets may remain cache-hot.
nonisolated public protocol RenderAnimation: AnyObject, Sendable {
    @discardableResult
    func update(at time: Float) -> Int

    /// Restore bind/reference state for a true animation-off A/B frame.
    @discardableResult
    func resetToBindPose() -> Int
}

nonisolated extension RenderAnimation {
    @discardableResult
    public func resetToBindPose() -> Int {
        0
    }
}

/// An actor that plays a clip other actors may share. The scene samples each
/// shared clip once per frame and hands the pose to every actor that plays it,
/// so a crowd on one idle costs one sample.
nonisolated public protocol SharedPoseAnimation: RenderAnimation {
    /// The actor's form ID, which keys its ragdoll pose override.
    var actorFormID: UInt32 { get }
    /// Identifies the shared clip. Actors with equal keys get one sample.
    var sharedClipKey: ObjectIdentifier { get }
    /// Samples the shared clip. Nil means the clip failed and every actor
    /// playing it keeps its last pose this frame.
    func sampleSharedPose(at time: Float) -> SkeletonPose?
    /// Applies a pose to the actor's meshes. A mesh already in
    /// `updatedMeshes` is skipped. Returns the number of bones updated.
    func apply(
        _ pose: SkeletonPose,
        updating updatedMeshes: inout Set<ObjectIdentifier>
    ) -> Int
}
