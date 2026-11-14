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
            eye: view.position, pivot: frameInput.cameraPivot,
            candidates: actorCameraCandidates(), seconds: seconds
        )
        fadeTimers.depthOfFieldFocus.advance(
            angles: SIMD3(view.pitch, 0, view.yaw), position: view.position,
            interior: activeLighting != nil, seconds: seconds
        )
    }

    /// One candidate per drawn actor, with the world box of each of its shapes as drawn
    /// this frame. A seated rider's shapes sit where its seat idle puts them, so riders
    /// that share one root on a cart stay apart.
    private func actorCameraCandidates() -> [ActorCameraFade.Candidate] {
        var shapes: [UInt32: [ModelBounds]] = [:]
        for groups in actorGroupsByOwner.values {
            for group in groups {
                for placed in group.instances {
                    let instance = drawn(placed)
                    guard instance.referenceFormID != 0, let box = instance.bounds else { continue }
                    shapes[instance.referenceFormID, default: []].append(box)
                }
            }
        }
        if isPlayerBodyVisible, let body = frameInput.rigs.body?.render {
            for list in [body.opaque, body.alphaTested] {
                for group in list {
                    for instance in group.instances {
                        if let box = instance.bounds {
                            shapes[Self.playerFormID, default: []].append(box)
                        }
                    }
                }
            }
        }
        var candidates: [ActorCameraFade.Candidate] = []
        candidates.reserveCapacity(shapes.count)
        for (formID, boxes) in shapes {
            candidates.append(ActorCameraFade.Candidate(
                formID: formID, shapes: boxes, isPlayer: formID == Self.playerFormID
            ))
        }
        // Fixed order, so a tie between two hits picks the same actor every run.
        candidates.sort { $0.formID < $1.formID }
        return candidates
    }
}
