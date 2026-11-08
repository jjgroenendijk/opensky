public import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// One file in the save list. `summary` is nil when the file cannot be read, so the
/// list still shows it and says why.
nonisolated public struct OpenSkySaveSlotListing: Equatable, Sendable {
    public let slot: String
    public let modified: Date
    public let summary: OpenSkySaveSummaryFile?
    public let error: String?

    public init(
        slot: String,
        modified: Date,
        summary: OpenSkySaveSummaryFile?,
        error: String?
    ) {
        self.slot = slot
        self.modified = modified
        self.summary = summary
        self.error = error
    }
}
