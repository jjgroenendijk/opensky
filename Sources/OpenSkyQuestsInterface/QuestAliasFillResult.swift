import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// What one fill pass produced: the table, why each empty alias is empty, and
/// whether the quest is allowed to start with it.
nonisolated public struct QuestAliasFillResult: Equatable, Sendable {
    /// The filled table, ready to be stored as a component.
    public let state: QuestAliasState
    /// Reason-tagged count of every alias left empty.
    public let skipped: QuestAliasTally
    /// Non-optional aliases that an implemented fill type failed to fill, in
    /// alias-list order. Non-empty means the quest must not start.
    public let unfilledRequired: [UInt32]

    /// Whether the quest may start with this table, which is the documented
    /// meaning of the Optional checkbox.
    public var canStartQuest: Bool {
        unfilledRequired.isEmpty
    }

    public init(state: QuestAliasState, skipped: QuestAliasTally, unfilledRequired: [UInt32]) {
        self.state = state
        self.skipped = skipped
        self.unfilledRequired = unfilledRequired
    }
}
