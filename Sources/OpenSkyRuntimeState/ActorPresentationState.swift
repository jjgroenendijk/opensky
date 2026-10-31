// How one actor is drawn beyond its records: which head it shows, and an eye
// texture set a script forced on it (`Actor.SetEyeTexture`). A change
// rebuilds the cell, as equipment does. The slot has no save tag, so it lasts
// for the session only. An idle prop is not here: `ActorPropPlayback` draws it.

import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

nonisolated public enum ActorHeadSource: Equatable, Sendable {
    /// The baked FaceGen mesh and tint, the game's own path.
    case baked
    /// The race and NPC head parts, loaded and tinted one by one.
    case assembled
}

/// A model riding one skeleton bone, such as a lute during an idle.
nonisolated public struct ActorPropAttachment: Equatable, Sendable {
    /// Relative to `Data/meshes`.
    public let modelPath: String
    public let bone: String

    public init(modelPath: String, bone: String) {
        self.modelPath = modelPath
        self.bone = bone
    }
}

nonisolated public struct ActorPresentationState: WorldStateComponent {
    public static let componentKind = WorldStateComponentKind.actorPresentation

    public var headSource: ActorHeadSource
    /// A TXST drawn on the eyes head part instead of its own.
    public var eyeTextureSet: FormID?

    public init(headSource: ActorHeadSource = .baked, eyeTextureSet: FormID? = nil) {
        self.headSource = headSource
        self.eyeTextureSet = eyeTextureSet
    }
}

nonisolated extension WorldStateComponentKind {
    public static let actorPresentation = Self(rawValue: "actorPresentation", order: 29)
}

extension WorldStateStore {
    /// `Actor.SetEyeTexture` on an actor loaded in `cell`. The texture lasts until the
    /// actor's 3D reloads, so `dropEyeTextures(in:)` clears it when the cell detaches.
    public func setEyeTexture(_ set: FormID, for actor: ReferenceKey, in cell: CellSceneLocation) {
        var state = component(ActorPresentationState.self, for: actor) ?? ActorPresentationState()
        state.eyeTextureSet = set
        self.set(state, for: actor, in: cell)
    }

    public func dropEyeTextures(in cell: CellSceneLocation) {
        for key in sortedDirtyKeys(in: cell) {
            guard
                var state = component(ActorPresentationState.self, for: key),
                state.eyeTextureSet != nil
            else { continue }
            state.eyeTextureSet = nil
            if state == ActorPresentationState() {
                reset(.actorPresentation, for: key)
            } else {
                set(state, for: key, in: cell)
            }
        }
    }
}
