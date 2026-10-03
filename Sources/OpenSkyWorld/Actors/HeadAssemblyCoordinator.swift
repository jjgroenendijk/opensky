// The per-actor switch between the baked FaceGen head and the assembled one.
// The switch is a world-state component, so the next cell build applies it.

import OpenSkyFormatsESM

/// What the head assembly coordinator reads from the session.
@MainActor
public protocol HeadAssemblyWorld: AnyObject {
    func actorHead(for actor: ReferenceKey) -> ActorHeadReadout?
    func presentation(of actor: ReferenceKey) -> ActorPresentationState?
    func updatePresentation(
        of actor: ReferenceKey,
        _ change: (inout ActorPresentationState) -> Void
    )
}

@MainActor
public final class HeadAssemblyCoordinator: HeadAssemblyControlProviding {
    weak var world: (any HeadAssemblyWorld)?

    public init() {}

    public func attach(world: any HeadAssemblyWorld) {
        self.world = world
    }

    public func headAssemblySnapshot(for actor: ReferenceKey?) -> HeadAssemblySnapshot {
        guard let actor, let world else {
            return HeadAssemblySnapshot(actor: nil, head: nil, requested: .baked)
        }
        return HeadAssemblySnapshot(
            actor: actor,
            head: world.actorHead(for: actor),
            requested: world.presentation(of: actor)?.headSource ?? .baked
        )
    }

    public func setHeadSource(_ source: ActorHeadSource, for actor: ReferenceKey) {
        world?.updatePresentation(of: actor) { $0.headSource = source }
    }
}
