// Drawing a reference the physics simulation is moving (issue #193, roadmap
// item 15.2).
//
// A cell build bakes one world matrix per instance and a cell is rebuilt only
// when its runtime state changes, which is the right answer for a world whose
// geometry is authored in place. A simulated rigid body breaks that assumption
// once per frame: the barrel a player shoves is somewhere new before the next
// draw, and rebuilding the cell it belongs to at sixty hertz is not an option.
//
// So the baked matrix stays, and the *difference* between where the build drew
// the reference and where the body is now is applied where instance transforms
// are uploaded. The difference is a rigid transform, so it composes with the
// baked matrix without knowing the reference's scale or the mesh's own local
// transform, and the draw group an instance belongs to — keyed by mesh and
// material — cannot change when the instance moves. The player body took the
// other road, rebuilding its draw groups on every move (RendererPlayerBody);
// it has to, because skinned geometry is placed by its bone palette as well as
// by its model matrix. Rigid clutter has no such constraint.
//
// Documented in docs/engine/dynamic-bodies.md.

import simd

nonisolated extension DrawInstance {
    /// This instance carried through a rigid transform: matrices recomposed and
    /// the culling AABB moved with them, so a body that has left its baked
    /// bounds is still drawn.
    func moved(by delta: float4x4) -> DrawInstance {
        let matrix = delta * modelMatrix
        return DrawInstance(
            modelMatrix: matrix,
            normalMatrix: MatrixMath.normalMatrix(matrix),
            bounds: bounds?.transformed(by: delta),
            castsShadows: castsShadows,
            receivesPointLights: receivesPointLights,
            receivesShadows: receivesShadows,
            referenceFormID: referenceFormID
        )
    }
}

extension Renderer {
    /// The instance as this frame should draw it: the baked one for everything
    /// the world places, and the moved one for a reference a rigid body owns.
    ///
    /// The identity check comes first and settles it for every ordinary
    /// instance without touching the dictionary, so a scene with no physics in
    /// it pays one integer comparison per instance. A body resting exactly
    /// where it was placed is absent from the map rather than present with an
    /// identity delta, so settled clutter costs the same as static clutter.
    func drawn(_ instance: DrawInstance) -> DrawInstance {
        guard
            instance.referenceFormID != 0,
            let delta = dynamicInstanceDeltas[instance.referenceFormID]
        else { return instance }
        return instance.moved(by: delta)
    }
}
