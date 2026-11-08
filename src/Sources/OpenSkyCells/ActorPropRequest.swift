// The idle props an actor holds, such as a broom or a lute. They load on the cell
// build runner, beside the cell builds, because they share its caches.

public import OpenSkyFormatsESM
public import OpenSkyRendering
import OpenSkyRuntimeState
public import OpenSkyTerrain
public import OpenSkyWorldInterface

/// One idle prop to load for one actor, on the actor's own rig.
nonisolated public struct ActorPropRequest: Equatable, Sendable {
    public let actor: FormID
    public let prop: ActorPropAttachment
    public let skeletonPath: String

    public init(actor: FormID, prop: ActorPropAttachment, skeletonPath: String) {
        self.actor = actor
        self.prop = prop
        self.skeletonPath = skeletonPath
    }
}

nonisolated public struct ActorPropLoadResult: Sendable {
    public let request: ActorPropRequest
    public let result: Result<RenderModel, any Error>
    /// What the load put in the caches, which no cell build lists.
    public let assets: CellAssets
}
