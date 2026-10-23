// The Head Assembly section's seam: the head part set of one actor and the
// switch between its baked and assembled head.

import OpenSkyRendering
import OpenSkyRuntimeState

/// What one actor's head is built from after the last cell build.
nonisolated public struct ActorHeadReadout: Equatable, Sendable {
    public let source: ActorHeadSource
    public let parts: HeadPartSet
    public let hasBakedHead: Bool
    /// Parts whose model loaded; the rest are asset skips.
    public let loadedPartCount: Int

    public init(
        source: ActorHeadSource,
        parts: HeadPartSet,
        hasBakedHead: Bool,
        loadedPartCount: Int
    ) {
        self.source = source
        self.parts = parts
        self.hasBakedHead = hasBakedHead
        self.loadedPartCount = loadedPartCount
    }

    public init(assembly: ActorAssembly<ActorRenderAsset>) {
        let loaded = assembly.models.count {
            if case .headPart = $0.role {
                return true
            }
            return false
        }
        let assembled = assembly.visual.headSource == .assembled && loaded > 0
        self.init(
            source: assembled ? .assembled : .baked,
            parts: assembly.visual.headParts,
            hasBakedHead: assembly.visual.faceGenMeshPath != nil,
            loadedPartCount: loaded
        )
    }
}
