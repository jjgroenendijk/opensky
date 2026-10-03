// The exclusive branch a speaker is in, keyed by the speaker's `ReferenceKey`.
// "Once the NPC is marked as in the Exclusive Branch, he will act as if that
// branch is a valid Blocking branch until he says a line of dialogue from a
// different (non-Exclusive) branch" (<https://ck.uesp.net/wiki/Dialogue_Branch>).

import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

nonisolated public struct DialogueBranchState: WorldStateComponent, Sendable {
    /// The DLBR with the exclusive flag the speaker last said a line from.
    public let exclusiveBranch: FormID

    public static var componentKind: WorldStateComponentKind {
        .dialogueBranch
    }

    public init(exclusiveBranch: FormID) {
        self.exclusiveBranch = exclusiveBranch
    }
}

nonisolated extension WorldStateComponentKind {
    /// A speaker's exclusive branch. Keyed by the speaker's placement.
    public static let dialogueBranch = Self(
        rawValue: "dialogueBranch", order: 24, affectsCellBuild: false
    )
}
