// The actor the camera comes too close to fades out, as in the game, so the view never
// shows the inside of a body (docs/engine/graphics-options.md#actor-fade-near-the-camera).

import OpenSkyFormatsCore
public import OpenSkyRenderCore
import simd

extension Renderer {
    /// The player's reference.
    static let playerFormID: UInt32 = 0x14

    /// This frame's fade of each actor near the camera, by its reference.
    public var actorCameraFadeOuts: [UInt32: Float] {
        fadeTimers.actorCamera.fadeOuts
    }

    /// How much the view centre counts in a "Use Target" depth of field focus.
    public var depthOfFieldFocus: DepthOfFieldFocus {
        fadeTimers.depthOfFieldFocus
    }

    /// Steps the timers that follow the view: the actor camera fade, from where each actor
    /// stands now, and the centre weight of the depth of field focus.
    func advanceViewTimers(seconds: Float) {
        let view = frameInput.view
        fadeTimers.actorCamera.advance(
            eye: view.position, candidates: actorCameraCandidates(), seconds: seconds
        )
        fadeTimers.depthOfFieldFocus.advance(
            angles: SIMD3(view.pitch, 0, view.yaw), position: view.position,
            interior: activeLighting != nil, seconds: seconds
        )
    }

    /// One candidate per drawn actor: its axis and radius from the bounds of its shapes.
    private func actorCameraCandidates() -> [ActorCameraFade.Candidate] {
        var bounds: [UInt32: (min: SIMD3<Float>, max: SIMD3<Float>)] = [:]
        for groups in actorGroupsByOwner.values {
            for group in groups {
                for placed in group.instances {
                    let instance = drawn(placed)
                    guard instance.referenceFormID != 0, let box = instance.bounds else { continue }
                    let known = bounds[instance.referenceFormID] ?? (box.min, box.max)
                    bounds[instance.referenceFormID] = (
                        simd_min(known.min, box.min), simd_max(known.max, box.max)
                    )
                }
            }
        }
        return bounds.map { formID, box in
            let size = box.max - box.min
            return ActorCameraFade.Candidate(
                formID: formID,
                feet: SIMD3((box.min.x + box.max.x) / 2, (box.min.y + box.max.y) / 2, box.min.z),
                height: size.z,
                radius: min(size.x, size.y) / 2,
                isPlayer: formID == Self.playerFormID
            )
        }
    }
}
