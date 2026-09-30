import Foundation
import OpenSkyFormatsESM

/// Where a chosen response's result scripts go. A seam, so dialogue works in
/// tests and sessions without a VM. In a real session the Papyrus world bridge
/// conforms.
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
