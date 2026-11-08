import Foundation
import OpenSkyAudio
import OpenSkyFormatsCore
import OpenSkyGameData

nonisolated public enum MovieOutcome: Equatable, Sendable {
    case finished
    case skipped
    case failed(String)
}

nonisolated public struct MoviePlaybackReadout: Equatable, Sendable {
    public var fileName: String?
    public var loading: Bool
    /// The frame on screen, nil before the first one.
    public var frame: Int?
    public var frameCount: Int?
    public var interruptible: Bool
    public var lastOutcome: MovieOutcome?

    public init(
        fileName: String? = nil,
        loading: Bool,
        frame: Int? = nil,
        frameCount: Int? = nil,
        interruptible: Bool,
        lastOutcome: MovieOutcome? = nil
    ) {
        self.fileName = fileName
        self.loading = loading
        self.frame = frame
        self.frameCount = frameCount
        self.interruptible = interruptible
        self.lastOutcome = lastOutcome
    }
}
