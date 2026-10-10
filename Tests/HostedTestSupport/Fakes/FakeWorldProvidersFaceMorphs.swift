// FaceMorphControlProviding part of the shared panel fake.

import Foundation
@testable import OpenSkyWorld

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

struct FakeFaceState {
    var snapshot = FaceMorphControlSnapshot.empty
    var automaticBlinkingEnabled = true
    var dialogueExpressionsEnabled = true
    var headTrackingEnabled = true
    var headTrackingReadout = ""
}

extension FakeWorldProviders {
    var faceMorphSnapshot: FaceMorphControlSnapshot {
        get { faceState.snapshot }
        set { faceState.snapshot = newValue }
    }

    var automaticBlinkingEnabled: Bool {
        get { faceState.automaticBlinkingEnabled }
        set { faceState.automaticBlinkingEnabled = newValue }
    }

    var dialogueExpressionsEnabled: Bool {
        get { faceState.dialogueExpressionsEnabled }
        set { faceState.dialogueExpressionsEnabled = newValue }
    }

    var headTrackingEnabled: Bool {
        get { faceState.headTrackingEnabled }
        set { faceState.headTrackingEnabled = newValue }
    }

    var headTrackingReadout: String {
        faceState.headTrackingReadout
    }
}
