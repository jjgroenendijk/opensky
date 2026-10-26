// The port through which a higher layer poses effect models: a model whose nodes move,
// by its own controllers or by its effect graph, draws as its own posed copy.
// See docs/rendering/visual-effects.md#posed-effect-models.

import OpenSkyRenderCore
import OpenSkyRendering

/// One effect drawn as its own copy, posed by `animation` each frame.
nonisolated public struct PosedEffectModel: Sendable {
    public let model: RenderModel
    public let animation: any RenderAnimation

    public init(model: RenderModel, animation: any RenderAnimation) {
        self.model = model
        self.animation = animation
    }
}

@MainActor
public protocol EffectModelPosing: AnyObject {
    /// Steps the models that move and returns their copies by instance id. A model left
    /// out draws the shared copy. An id missing from `models` has ended.
    func pose(_ models: [VisualEffectModel], deltaTime: Float) -> [Int: PosedEffectModel]
}
