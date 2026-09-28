// Main-app inspection seam for actor-local FaceGen expression weights.

import Foundation

nonisolated struct FaceMorphControlSnapshot: Equatable {
    static let empty = FaceMorphControlSnapshot(
        actor: nil,
        targetNames: [],
        weights: [:],
        pairedPaths: [],
        associationMisses: [],
        unknownTargetCount: 0
    )

    let actor: FormID?
    let targetNames: [String]
    let weights: [String: Float]
    let pairedPaths: [String]
    let associationMisses: [String]
    let unknownTargetCount: Int
}

@MainActor
protocol FaceMorphControlProviding: AnyObject {
    var faceMorphSnapshot: FaceMorphControlSnapshot { get }

    func setFaceMorphWeight(_ weight: Float, target: String)
    func resetFaceMorphWeights()
}
