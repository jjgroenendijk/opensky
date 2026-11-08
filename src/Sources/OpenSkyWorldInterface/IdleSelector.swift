import Foundation
public import OpenSkyFormatsESM
import OpenSkyGameData

/// One candidate the selector looked at, and what happened to it.
nonisolated public struct IdleCandidateTrace: Equatable, Sendable {
    nonisolated public enum Verdict: Equatable, Sendable {
        case chosen
        /// Its conditions passed, but another candidate was chosen.
        case passed
        /// The Creation Kit name of the first condition that failed.
        case rejected(String)
        /// The selector stopped before it, or its parent failed.
        case notReached
        /// A do-once marker already played it.
        case alreadyPlayed
        /// Its conditions passed, but it sends no event and no child passed.
        case noAnimation
    }

    public let id: ResolvedFormID
    public let editorID: String?
    /// 0 for a marker entry or a root; 1 for its child, and so on.
    public let depth: Int
    public let verdict: Verdict

    public init(
        id: ResolvedFormID,
        editorID: String?,
        depth: Int,
        verdict: Verdict
    ) {
        self.id = id
        self.editorID = editorID
        self.depth = depth
        self.verdict = verdict
    }
}
