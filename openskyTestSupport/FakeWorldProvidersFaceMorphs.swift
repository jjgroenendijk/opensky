// FaceMorphControlProviding half of the shared panel fake (issue #207).

import Foundation
@testable import opensky

extension FakeWorldProviders {
    func setFaceMorphWeight(_ weight: Float, target: String) {
        guard faceMorphSnapshot.targetNames.contains(target) else { return }
        var weights = faceMorphSnapshot.weights
        weights[target] = min(max(weight, 0), 1)
        faceMorphSnapshot = FaceMorphControlSnapshot(
            actor: faceMorphSnapshot.actor,
            targetNames: faceMorphSnapshot.targetNames,
            weights: weights,
            pairedPaths: faceMorphSnapshot.pairedPaths,
            associationMisses: faceMorphSnapshot.associationMisses,
            unknownTargetCount: faceMorphSnapshot.unknownTargetCount
        )
    }

    func resetFaceMorphWeights() {
        faceMorphSnapshot = FaceMorphControlSnapshot(
            actor: faceMorphSnapshot.actor,
            targetNames: faceMorphSnapshot.targetNames,
            weights: [:],
            pairedPaths: faceMorphSnapshot.pairedPaths,
            associationMisses: faceMorphSnapshot.associationMisses,
            unknownTargetCount: faceMorphSnapshot.unknownTargetCount
        )
    }
}
