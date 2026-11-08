import Foundation
import OpenSkyFormatsESM
import OpenSkyWorldState

/// Header metadata describing when and by what a save was written.
///
/// The timestamp is a caller-supplied unix time in seconds rather than
/// something the encoder reads from the clock, because determinism tests must
/// be able to produce the same bytes twice, and because a replayed or migrated
/// save should keep its original creation time.
nonisolated public struct SaveCreationMetadata: Equatable, Sendable {
    /// Seconds since the unix epoch, injected by the caller.
    public let creationTimestamp: UInt64
    /// Human-readable version of the build that wrote the file.
    public let appVersion: String

    public init(creationTimestamp: UInt64, appVersion: String) {
        self.creationTimestamp = creationTimestamp
        self.appVersion = appVersion
    }
}
