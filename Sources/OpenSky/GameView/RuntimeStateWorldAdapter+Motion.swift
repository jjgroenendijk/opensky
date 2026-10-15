// The motion seam of the live condition context: where each reference a run-on can
// name stands, and how the player and the path-following actors move.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyWorld
import OpenSkyWorldState

extension RuntimeStateWorldAdapter {
    func motionResolution(references: RuntimeReferenceIndex) -> MotionConditionResolution {
        var facts = game.streamer?.npcMovement.motionFacts() ?? [:]
        for entry in references.sortedEntries() where facts[entry.key] == nil {
            let state = game.worldState.resolvedState(for: entry)
            let moved = game.streamer?.npcTransform(for: entry.key)
            facts[entry.key] = ReferenceMotionFacts(
                position: moved?.position ?? state.transform.position,
                rotation: moved?.rotation ?? state.transform.rotation
            )
        }
        if let renderer = game.renderer {
            let status = renderer.locomotion.status
            facts[.player] = ReferenceMotionFacts(
                position: renderer.walkController.feetPosition,
                rotation: SIMD3(0, 0, NPCYawMath.heading(fromYaw: status.yaw)),
                velocity: SIMD3(
                    status.horizontalVelocity.x, status.horizontalVelocity.y,
                    status.verticalVelocity
                )
            )
        }
        return MotionConditionResolution(facts: facts)
    }
}
