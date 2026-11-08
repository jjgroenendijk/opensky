import Foundation
import OpenSkyConditions
public import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct QuestTargetMarker: Equatable, Sendable {
    public var quest = FormID(0)
    public var objective: UInt16 = 0
    public let text: String
    /// The reference the marker stands on: the target, or what holds it.
    public let anchor: ReferenceKey
    public let position: SIMD3<Float>

    public init(
        quest: FormID = FormID(0),
        objective: UInt16 = 0,
        text: String,
        anchor: ReferenceKey,
        position: SIMD3<Float>
    ) {
        self.quest = quest
        self.objective = objective
        self.text = text
        self.anchor = anchor
        self.position = position
    }
}
