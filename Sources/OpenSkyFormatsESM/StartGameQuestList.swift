// A `Data/Seq/<plugin>.seq` file: the quests a plugin starts when a game
// begins, as bare little-endian FormIDs relative to that plugin's masters.
// Layout and sources: docs/formats/seq.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public enum StartGameQuestListError: Error, Equatable, Sendable {
    /// The byte count is not a multiple of 4, so the last FormID is cut off.
    case truncated(byteCount: Int)
}

nonisolated public struct StartGameQuestList: Equatable, Sendable {
    /// Raw FormIDs in file order, master index as the owning plugin sees it.
    public let quests: [FormID]

    public init(data: Data) throws(StartGameQuestListError) {
        guard data.count.isMultiple(of: 4) else {
            throw .truncated(byteCount: data.count)
        }
        var quests: [FormID] = []
        quests.reserveCapacity(data.count / 4)
        var reader = BinaryReader(data)
        while reader.bytesRemaining >= 4 {
            guard let raw = try? reader.readUInt32() else { break }
            quests.append(FormID(raw))
        }
        self.quests = quests
    }

    /// The VFS path of a plugin's list, such as `seq\skyrim.seq`.
    public static func path(forPlugin plugin: String) -> String {
        let stem = (plugin as NSString).deletingPathExtension
        return "seq\\\(stem).seq"
    }
}
