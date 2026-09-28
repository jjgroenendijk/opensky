// Index of ASPC acoustic-space records by FormID. The runtime interior-
// ambience path (M9.2.2) resolves CELL.XCAS -> ASPC.SNAM (direct ambient
// sound) and ASPC.RDAT (region whose type-7 sound area is borrowed for the
// interior). Mirrors the SoundRecordStore shape: built once from an ESMFile,
// holds only value types after construction.

import Foundation

nonisolated final class AcousticSpaceStore {
    let spaces: [UInt32: AcousticSpace]

    init(file: ESMFile) {
        spaces = Self.index(file, type: "ASPC") { try? AcousticSpace(record: $0) }
    }

    func acousticSpace(_ id: FormID) -> AcousticSpace? {
        spaces[id.rawValue]
    }

    private static func index<Value>(
        _ file: ESMFile,
        type: FourCC,
        decode: (ESMRecord) -> Value?
    ) -> [UInt32: Value] {
        var values: [UInt32: Value] = [:]
        guard let group = file.topGroup(of: type), let children = try? group.children() else {
            return values
        }
        for case let .record(record) in children where record.type == type {
            if let value = decode(record) {
                values[record.formID] = value
            }
        }
        return values
    }
}
