// Main-app inspection seam for actor-local FaceGen expression weights.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct FaceMorphControlSnapshot: Equatable, Sendable {
    public static let empty = FaceMorphControlSnapshot(
        actor: nil,
        targetNames: [],
        weights: [:],
        pairedPaths: [],
        associationMisses: [],
        unknownTargetCount: 0
    )

    public let actor: FormID?
    public let targetNames: [String]
    public let weights: [String: Float]
    public let pairedPaths: [String]
    public let associationMisses: [String]
    public let unknownTargetCount: Int
    /// The automatic part: emotion and blinking.
    public let expressionWeights: [String: Float]

    public init(
        actor: FormID?,
        targetNames: [String],
        weights: [String: Float],
        pairedPaths: [String],
        associationMisses: [String],
        unknownTargetCount: Int,
        expressionWeights: [String: Float] = [:]
    ) {
        self.actor = actor
        self.targetNames = targetNames
        self.weights = weights
        self.pairedPaths = pairedPaths
        self.associationMisses = associationMisses
        self.unknownTargetCount = unknownTargetCount
        self.expressionWeights = expressionWeights
    }
}

@MainActor
public protocol FaceMorphControlProviding: AnyObject {
    var faceMorphSnapshot: FaceMorphControlSnapshot { get }
    /// Every loaded face blinks on its own.
    var automaticBlinkingEnabled: Bool { get set }
    /// A speaker's face shows the emotion of the line it says.
    var dialogueExpressionsEnabled: Bool { get set }
    /// Actors turn their heads toward what they look at.
    var headTrackingEnabled: Bool { get set }
    /// What the selected actor looks at, and how far its head is turned.
    var headTrackingReadout: String { get }

    func setFaceMorphWeight(_ weight: Float, target: String)
    func resetFaceMorphWeights()
}
