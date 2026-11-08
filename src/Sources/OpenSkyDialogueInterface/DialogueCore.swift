public import OpenSkyFormatsESM

/// What the conversation does after a response is said to its end.
nonisolated public enum DialogueResponseEnd: Equatable, Sendable {
    case close
    /// Invisible Continue: say this linked response now, with no prompt.
    case continueWith(FormID)
    /// Show these topics. The coordinator already stored them as the selection.
    case topics(DialogueSelection)
    /// No runtime, so the list stays as it was.
    case unchanged
}
