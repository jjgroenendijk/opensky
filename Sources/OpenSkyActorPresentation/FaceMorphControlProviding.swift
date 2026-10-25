// Main-app inspection seam for actor-local FaceGen expression weights.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct FaceMorphControlSnapshot: Equatable, Sendable {
    public static let empty = FaceMorphControlSnapshot(
        actor: nil,
        pairedPaths: [],
        associationMisses: [],
        unknownTargetCount: 0
    )

    public let actor: FormID?
    public let pairedPaths: [String]
    public let associationMisses: [String]
    public let unknownTargetCount: Int

    public init(
        actor: FormID?,
        pairedPaths: [String],
        associationMisses: [String],
        unknownTargetCount: Int
    ) {
        self.actor = actor
        self.pairedPaths = pairedPaths
        self.associationMisses = associationMisses
        self.unknownTargetCount = unknownTargetCount
    }
}
