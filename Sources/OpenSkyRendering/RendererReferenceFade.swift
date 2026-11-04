// Distance fades of placed references on the CPU path. The GPU cull kernel applies
// the same rule (`cullFade` in CullingMotionShaders.metal).

import OpenSkyFormatsCore
import OpenSkyRenderCore
import simd

/// What one cull dispatch needs for the distance fades.
struct CullFade {
    let distances: ReferenceFadeDistances
    let viewer: SIMD3<Float>
}

extension DrawInstance {
    /// Actors follow the actor multiplier, references a rigid body moves the item one,
    /// and other cell statics the object one. LOD, terrain, and water never fade.
    var fadeCategory: ReferenceFadeCategory {
        if layer.contains(.actors) {
            return .actor
        }
        guard layer.contains(.statics) else { return .none }
        return referenceFormID != 0 ? .item : .object
    }
}

extension Renderer {
    /// 0 whole, up to 1 dissolved; nil when `instance` is past its reach.
    func distanceFade(of instance: DrawInstance) -> Float? {
        guard referenceFades.isOn, let bounds = instance.bounds else { return 0 }
        return referenceFades.fade(
            instance.fadeCategory, lower: bounds.min, upper: bounds.max,
            viewer: frameInput.view.position
        )
    }
}
