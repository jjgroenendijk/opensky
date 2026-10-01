// Where a dialogue response's recorded line lives in the archives:
//   sound\voice\<plugin>\<voice type editor ID>\<quest>_<topic>_<8 hex FormID>_<n>.fuz
// No record points at a voice file, so the path is rebuilt from names. The
// shortening rule for the name was derived from the install's own archive listing
// (`openskycli audio voice-sweep`); docs/formats/fuz.md holds the evidence.
// Pure: the caller supplies the strings, so table tests can pin the rule.

import Foundation
import OpenSkyFormatsESM

nonisolated public enum VoiceFilePath: Sendable {
    /// Archive directory every voice file lives under, as a canonical VFS key.
    public static let root = "sound\\voice"

    /// Characters the quest editor ID keeps once the pair is too long to
    /// spell out.
    public static let questNameLimit = 10
    /// Characters the topic editor ID keeps once the pair is too long to
    /// spell out.
    public static let topicNameLimit = 15
    /// Characters the two editor IDs may occupy together, underscore excluded,
    /// before either is shortened at all.
    public static let combinedNameBudget = questNameLimit + topicNameLimit

    /// The lowercased `<quest>_<topic>` stem. The two names share 25 characters:
    /// a quest that fits beside the topic's reserved 15 stays whole, otherwise it
    /// drops to 10, and the topic takes the rest. Either name may be empty.
    public static func stem(quest: String?, topic: String?) -> String {
        let quest = (quest ?? "").lowercased()
        let topic = (topic ?? "").lowercased()
        let reserved = min(topic.count, topicNameLimit)
        let questLength = quest.count <= combinedNameBudget - reserved
            ? quest.count
            : questNameLimit
        let topicLength = min(topic.count, combinedNameBudget - questLength)
        return "\(quest.prefix(questLength))_\(topic.prefix(topicLength))"
    }

    /// The four pieces a voice file's name is built from. `objectID` is the
    /// FormID as the exporting plugin numbered it (`exportedFormID`), and
    /// `responseNumber` is TRDT's one-based response number.
    nonisolated public struct Name: Equatable, Sendable {
        public let quest: String?
        public let topic: String?
        public let objectID: UInt32
        public let responseNumber: Int
    }

    /// One voice file's name, without a directory.
    public static func fileName(_ name: Name) -> String {
        let identifier = String(format: "%08x", name.objectID)
        let stem = stem(quest: name.quest, topic: name.topic)
        return "\(stem)_\(identifier)_\(name.responseNumber).fuz"
    }

    /// Full canonical VFS key for one line.
    public static func path(plugin: String, voiceType: String, name: Name) -> String {
        directory(plugin: plugin, voiceType: voiceType) + "\\" + fileName(name)
    }

    /// Directory holding every line one voice type says for one plugin.
    public static func directory(plugin: String, voiceType: String) -> String {
        "\(root)\\\(plugin.lowercased())\\\(voiceType.lowercased())"
    }

    /// The FormID as it appears in a voice file name. The Creation Kit writes the
    /// plugin's own index as zero, so index `masterCount` is cleared and a master's
    /// index stays. Dawnguard lines read `00xxxxxx`; its Update.esm overrides keep `01`.
    public static func exportedFormID(_ id: FormID, masterCount: Int) -> UInt32 {
        id.masterIndex >= masterCount ? id.objectID : id.rawValue
    }
}
