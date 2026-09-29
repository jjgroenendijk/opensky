import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// Where a chosen response's result scripts go.
///
/// A seam rather than a direct call into `PapyrusWorldRuntime` for the reason
/// `PapyrusWorldQuestBridge` is one: the dialogue layer compiles into
/// `openskycli` and is tested without a VM, and a session with no script
/// runtime must still be able to hold a conversation. The conformer in a real
/// session is the Papyrus world bridge.
@MainActor
public protocol DialogueFragmentDispatching: AnyObject, Sendable {
    /// Instantiates the response's result script if needed and enqueues the
    /// fragment for `phase`.
    ///
    /// - Returns: the function names enqueued, which is empty when the response
    ///   declares no fragment for that phase or when its script is unavailable.
    @discardableResult
    func runTopicInfoFragments(
        of info: TopicInfo,
        key: ReferenceKey,
        phase: TopicInfoFragmentPhase
    ) -> [String]
}
