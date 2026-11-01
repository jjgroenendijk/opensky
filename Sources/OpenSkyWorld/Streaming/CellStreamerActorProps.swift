// Idle props on live actors. A prop is drawn beside its actor's cell scene, not
// baked into it, so starting or ending an idle rebuilds no cell. A rebuilt cell
// brings a new actor playback, and the next view scene binds the prop to it.

import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyRendering
import OpenSkyRuntimeState
import OpenSkyTerrain

/// The prop one actor shows. `model` is nil while the build queue loads it.
nonisolated public struct ActorPropDraw {
    public let prop: ActorPropAttachment
    public var model: RenderModel?
    /// The prop's keys in the builder's caches, evicted when the prop goes.
    public var assets: CellAssets

    public init(
        prop: ActorPropAttachment,
        model: RenderModel? = nil,
        assets: CellAssets = .init()
    ) {
        self.prop = prop
        self.model = model
        self.assets = assets
    }
}

extension CellStreamer {
    /// Shows `prop` on a resident actor, or removes the actor's prop with nil.
    public func setActorProp(_ prop: ActorPropAttachment?, on actor: FormID) {
        guard actorProps[actor]?.prop != prop else { return }
        let removed = actorProps.removeValue(forKey: actor)
        let wasDrawn = removed?.model != nil
        if let prop, let playback = residentActorPlayback(for: actor) {
            actorProps[actor] = ActorPropDraw(prop: prop)
            runner.enqueueActorProp(ActorPropRequest(
                actor: actor, prop: prop, skeletonPath: playback.clip.skeletonMeshPath
            ))
        }
        if let removed {
            evictUnused(removed.assets)
        }
        if wasDrawn {
            sink(viewScene(), nil)
        }
    }

    /// Takes loaded prop models. Returns true when one became drawable.
    public func integrateActorProps() -> Bool {
        var changed = false
        for entry in runner.drainCompletedActorProps() {
            let actor = entry.request.actor
            // A prop replaced or removed while it loaded is dropped.
            guard actorProps[actor]?.prop == entry.request.prop else {
                evictUnused(entry.assets)
                continue
            }
            switch entry.result {
            case let .success(model):
                actorProps[actor]?.model = model
                actorProps[actor]?.assets = entry.assets
                changed = true
            case let .failure(error):
                actorProps.removeValue(forKey: actor)
                evictUnused(entry.assets)
                let path = entry.request.prop.modelPath
                Self.logger.warning(
                    """
                    [WARNING] idle prop \(path, privacy: .public) on \
                    \(actor.description, privacy: .public) did not load: \
                    \(String(describing: error), privacy: .public)
                    """
                )
            }
        }
        return changed
    }

    /// What the sink draws: the interior, or the resident exterior cells, plus
    /// every loaded prop whose actor is in it.
    public func viewScene() -> RenderScene {
        let base = interiorScene?.renderScene ?? composition.composedScene()
        let props = actorProps.sorted { $0.key.rawValue < $1.key.rawValue }
            .compactMap { actor, draw -> RenderScene? in
                guard let model = draw.model, let playback = base.actorPlayback(for: actor)
                else { return nil }
                return .actorProp(model, on: playback)
            }
        return props.isEmpty ? base : RenderScene(merging: [base] + props)
    }

    private func residentActorPlayback(for actor: FormID) -> ActorAnimationPlayback? {
        let scenes = interiorScene.map { [$0] } ?? Array(composition.cells.values)
        return scenes.lazy.compactMap { $0.renderScene.actorPlayback(for: actor) }.first
    }
}

extension CellStreamer {
    /// Drops the props of actors no loaded cell holds and returns their assets. The
    /// idle's own end cannot remove them, because it finds no reference by then.
    func takeDepartedActorProps() -> CellAssets {
        let scenes = (interiorScene.map { [$0] } ?? []) + Array(composition.cells.values)
        var departed = CellAssets()
        for (actor, draw) in actorProps
            where !scenes.contains(where: { $0.renderScene.actorPlayback(for: actor) != nil })
        {
            actorProps.removeValue(forKey: actor)
            departed.meshKeys.formUnion(draw.assets.meshKeys)
            departed.textureKeys.formUnion(draw.assets.textureKeys)
        }
        return departed
    }

    /// The keys of every prop that stays, so eviction keeps them.
    var actorPropAssets: CellAssets {
        actorProps.values.reduce(into: CellAssets()) { assets, draw in
            assets.meshKeys.formUnion(draw.assets.meshKeys)
            assets.textureKeys.formUnion(draw.assets.textureKeys)
        }
    }
}
