// Main-app inspection seam for actor-local FaceGen expression weights.

import Foundation
public import OpenSkyFormatsESM

nonisolated struct FaceMorphControlSnapshot: Equatable, Sendable {
    static let empty = FaceMorphControlSnapshot(
        actor: nil,
        pairedPaths: [],
        associationMisses: [],
        unknownTargetCount: 0
    )

    let actor: FormID?
    let pairedPaths: [String]
    let associationMisses: [String]
    let unknownTargetCount: Int
}
