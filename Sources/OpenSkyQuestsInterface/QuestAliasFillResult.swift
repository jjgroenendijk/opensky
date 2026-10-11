import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

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
    /// "Create Reference to Object" aliases, which the world fills once it made the reference.
    public let creations: [QuestAliasCreation]

    /// Whether the quest may start with this table, which is the documented
    /// meaning of the Optional checkbox.
    public var canStartQuest: Bool {
        unfilledRequired.isEmpty
    }

    public init(
        state: QuestAliasState, skipped: QuestAliasTally, unfilledRequired: [UInt32],
        creations: [QuestAliasCreation] = []
    ) {
        self.state = state
        self.skipped = skipped
        self.unfilledRequired = unfilledRequired
        self.creations = creations
    }
}

/// One alias that asks for a new reference of `base`, placed at `anchor`.
nonisolated public struct QuestAliasCreation: Equatable, Sendable {
    public let aliasID: UInt32
    /// The base object, in the quest store's FormID space.
    public let base: FormID
    public let anchor: ReferenceKey

    public init(aliasID: UInt32, base: FormID, anchor: ReferenceKey) {
        self.aliasID = aliasID
        self.base = base
        self.anchor = anchor
    }
}
