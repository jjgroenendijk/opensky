// Idle props on live actors. A prop is drawn beside its actor's cell scene, not
// baked into it, so starting or ending an idle rebuilds no cell. A rebuilt cell
// brings a new actor playback, and the next view scene binds the prop to it.

import OpenSkyFormatsESM
import OpenSkyRendering
import OSLog

/// The prop one actor shows. `model` is nil while the build queue loads it.
nonisolated public struct ActorPropDraw {
    public let prop: ActorPropAttachment
    public var model: RenderModel?
}

extension CellStreamer {
    /// Shows `prop` on a resident actor, or removes the actor's prop with nil.
    public func setActorProp(_ prop: ActorPropAttachment?, on actor: FormID) {
        guard actorProps[actor]?.prop != prop else { return }
        let wasDrawn = actorProps.removeValue(forKey: actor)?.model != nil
        if let prop, let playback = residentActorPlayback(for: actor) {
            actorProps[actor] = ActorPropDraw(prop: prop)
            runner.enqueueActorProp(ActorPropRequest(
                actor: actor, prop: prop, skeletonPath: playback.clip.skeletonMeshPath
            ))
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
            guard actorProps[actor]?.prop == entry.request.prop else { continue }
            switch entry.result {
            case let .success(model):
                actorProps[actor]?.model = model
                changed = true
            case let .failure(error):
                actorProps.removeValue(forKey: actor)
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
