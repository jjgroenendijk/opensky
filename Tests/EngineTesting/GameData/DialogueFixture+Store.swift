// The dialogue store over one synthetic dialogue plugin.

import FormatsTesting
import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData

extension DialogueFixture {
    public static func store(
        dialogueChildren: Data = Data(),
        voiceRecords: Data = Data(),
        branchRecords: Data = Data(),
        localized: Bool = false
    ) throws -> DialogueStore {
        let bytes = plugin(
            dialogueChildren: dialogueChildren,
            voiceRecords: voiceRecords,
            branchRecords: branchRecords,
            localized: localized
        )
        return try DialogueStore(file: ESMFile(data: bytes), pluginName: pluginName)
    }
}
