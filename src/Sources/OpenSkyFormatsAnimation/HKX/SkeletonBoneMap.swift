// Maps hkaSkeleton bones onto the NIF skeleton node names that skinning keys
// on. The two rigs differ (helper nodes on each side), so the map is partial,
// and every unmatched bone is reported with a reason, never dropped.
// Observed vanilla counts: docs/formats/hka-skeleton.md.

import Foundation

/// One HKX bone with no NIF node, or one NIF node with no HKX bone, plus the
/// reason it went unmatched.
nonisolated public struct SkeletonBoneMismatch: Equatable, Sendable {
    public let name: String
    public let reason: String
}

/// Result of matching HKX bone names against NIF node names, both directions.
/// Match is exact name equality — the vanilla rig shares bone names verbatim
/// between the two files, so no normalization is applied (it would mask real
/// divergence).
nonisolated public struct SkeletonBoneMap: Sendable {
    /// HKX bone names that also name a NIF node, in HKX bone order.
    public let matched: [String]
    /// HKX bones with no NIF node (control/attach helpers, rig-only bones).
    public let unmatchedHKX: [SkeletonBoneMismatch]
    /// NIF nodes with no HKX bone (mesh-only nodes the rig omits).
    public let unmatchedNIF: [SkeletonBoneMismatch]

    public var matchedCount: Int {
        matched.count
    }

    /// Builds the map. `nifNodeNames` is the NIF-side key set
    /// (NIFSkeleton.boneTransforms.keys).
    public init(hkxBoneNames: [String], nifNodeNames: Set<String>) {
        var matched: [String] = []
        var unmatchedHKX: [SkeletonBoneMismatch] = []
        for bone in hkxBoneNames {
            if nifNodeNames.contains(bone) {
                matched.append(bone)
            } else {
                unmatchedHKX.append(SkeletonBoneMismatch(
                    name: bone,
                    reason: "no NIF node (HKX-only: control/attach helper or rig-only bone)"
                ))
            }
        }
        let hkxSet = Set(hkxBoneNames)
        self.matched = matched
        self.unmatchedHKX = unmatchedHKX
        unmatchedNIF = nifNodeNames.subtracting(hkxSet)
            .sorted()
            .map { SkeletonBoneMismatch(name: $0, reason: "no HKX bone (NIF-only node)") }
    }
}
