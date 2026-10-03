// The Head Assembly section's seam: the head part set of one actor and the
// switch between its baked and assembled head.

import OpenSkyFormatsESM
import OpenSkyRendering

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

nonisolated public struct HeadAssemblySnapshot: Equatable, Sendable {
    public let actor: ReferenceKey?
    /// Nil when the actor is not resident or has no humanoid head.
    public let head: ActorHeadReadout?
    /// The source the panel asked for, which the next build applies.
    public let requested: ActorHeadSource

    public init(actor: ReferenceKey?, head: ActorHeadReadout?, requested: ActorHeadSource) {
        self.actor = actor
        self.head = head
        self.requested = requested
    }
}

@MainActor
public protocol HeadAssemblyControlProviding: AnyObject {
    func headAssemblySnapshot(for actor: ReferenceKey?) -> HeadAssemblySnapshot
    /// Rebuilds the actor's cell with the chosen head.
    func setHeadSource(_ source: ActorHeadSource, for actor: ReferenceKey)
}

/// Lets the app's provider object stand in for its `HeadAssemblyCoordinator`.
public protocol HeadAssemblyControlForwarding: HeadAssemblyControlProviding {
    var headAssembly: HeadAssemblyCoordinator { get }
}

extension HeadAssemblyControlForwarding {
    public func headAssemblySnapshot(for actor: ReferenceKey?) -> HeadAssemblySnapshot {
        headAssembly.headAssemblySnapshot(for: actor)
    }

    public func setHeadSource(_ source: ActorHeadSource, for actor: ReferenceKey) {
        headAssembly.setHeadSource(source, for: actor)
    }
}
