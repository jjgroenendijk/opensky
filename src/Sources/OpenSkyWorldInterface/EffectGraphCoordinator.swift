import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
public import OpenSkyFormatsESM
import OpenSkyGameData

/// One line of the effect graph readout.
nonisolated public struct EffectGraphRow: Equatable, Sendable {
    public let id: SubGraphID
    public let anchor: SubGraphAnchor
    public let name: String
    public let project: String
    public let activeState: String?
    /// The last actor event the graph declares and so took; nil before the first.
    public let lastEvent: String?
    public let takenCount: Int
    /// The NIF sequences the graph's last step played, in walk order.
    public let sequences: [String]

    public var actor: ReferenceKey? {
        guard case let .actor(key) = anchor else { return nil }
        return key
    }

    public init(
        id: SubGraphID,
        anchor: SubGraphAnchor,
        name: String,
        project: String,
        activeState: String?,
        lastEvent: String?,
        takenCount: Int,
        sequences: [String]
    ) {
        self.id = id
        self.anchor = anchor
        self.name = name
        self.project = project
        self.activeState = activeState
        self.lastEvent = lastEvent
        self.takenCount = takenCount
        self.sequences = sequences
    }
}
