// Live app bridge for the HUD & Interaction Face Morphs section.

import Foundation

extension GameViewController: FaceMorphControlProviding {
    var faceMorphSnapshot: FaceMorphControlSnapshot {
        guard let playback = selectedFaceMorphPlayback() else { return .empty }
        return FaceMorphControlSnapshot(
            actor: playback.actor,
            targetNames: playback.targetNames,
            weights: playback.weights,
            pairedPaths: playback.pairedPaths,
            associationMisses: playback.misses.map {
                "\($0.headPart): \($0.reason)"
            },
            unknownTargetCount: playback.unknownTargetCount
        )
    }

    func setFaceMorphWeight(_ weight: Float, target: String) {
        selectedFaceMorphPlayback()?.setWeight(weight, for: target)
    }

    func resetFaceMorphWeights() {
        selectedFaceMorphPlayback()?.resetToBindPose()
    }

    private func selectedFaceMorphPlayback() -> FaceMorphPlayback? {
        guard
            let renderer,
            let key = dialogue.model.speakerKey ?? streamer?.talk.speaker,
            let actor = streamer?.referenceEntry(key: key)?.placedActor?.formID
        else { return nil }
        return renderer.scene.animations.lazy
            .compactMap { $0 as? FaceMorphPlayback }
            .first { $0.actor == actor }
    }
}
