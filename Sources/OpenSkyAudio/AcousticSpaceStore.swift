// ASPC acoustic spaces by FormID. Interior ambience resolves CELL.XCAS to
// ASPC.SNAM (the ambient sound) and ASPC.RDAT (a region to borrow sounds from).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public final class AcousticSpaceStore {
    public let spaces: [UInt32: AcousticSpace]
    public let skippedRecords: SkippedRecords

    public convenience init(file: ESMFile) {
        self.init(loadOrder: LoadOrderPlugins(file: file))
    }

    public init(loadOrder: LoadOrderPlugins) {
        var skipped = SkippedRecords()
        spaces = loadOrder
            .indexRecords(of: "ASPC", skipped: &skipped) { try AcousticSpace(record: $0) }
        skippedRecords = skipped
    }

    public func acousticSpace(_ id: FormID) -> AcousticSpace? {
        spaces[id.rawValue]
    }
}
