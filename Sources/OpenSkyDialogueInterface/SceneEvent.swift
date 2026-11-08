import Foundation
public import OpenSkyFormatsESM

/// A line a dialogue action selected and marked said.
nonisolated public struct SceneLine: Equatable, Sendable {
    public let speaker: ReferenceKey
    public let topic: FormID
    public let info: FormID
    /// From the voice file when there is one, else from the text.
    public var seconds: Float = Self.defaultSeconds
    /// The actor the speaker looks at, from the action's `HTID` alias.
    public var lookAt: ReferenceKey?

    /// A line with no host to time it.
    public static let defaultSeconds: Float = 3

    public init(
        speaker: ReferenceKey,
        topic: FormID,
        info: FormID,
        seconds: Float = Self.defaultSeconds,
        lookAt: ReferenceKey? = nil
    ) {
        self.speaker = speaker
        self.topic = topic
        self.info = info
        self.seconds = seconds
        self.lookAt = lookAt
    }
}
