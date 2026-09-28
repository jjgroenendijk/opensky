// Where a dialogue response's recorded line lives in the archives.
//
// A voice file is addressed entirely by name — nothing in an INFO record
// points at one — so playing a line means rebuilding the path the Creation Kit
// wrote when it exported the recording:
//
//   sound\voice\<plugin file name>\<voice type editor ID>\<name>.fuz
//   <name> = <quest editor ID>_<topic editor ID>_<8 hex FormID>_<response number>
//
// The directory half is stated by the CreationKit wiki ("How to generate voice
// files by batch", https://ck.uesp.net/wiki/How_to_generate_voice_files_by_batch)
// and by the UESP dialogue pages. The file-name half is not: the community
// descriptions disagree about how a long quest or topic editor ID is shortened,
// and none of them mention that the two names share one budget. So the rule
// below was derived from the install's own archive listing — 75,408 `.fuz`
// entries walked by `openskycli audio voice-sweep`, which re-derives every name
// from the records and reports any that does not match. The derivation and its
// evidence are written up in docs/formats/fuz.md.
//
// Everything here is pure: no VFS, no records, no engine state. The caller
// supplies the strings, which is what lets the rule be pinned by table tests.

import Foundation

nonisolated enum VoiceFilePath {
    /// Archive directory every voice file lives under, as a canonical VFS key.
    static let root = "sound\\voice"

    /// Characters the quest editor ID keeps once the pair is too long to
    /// spell out.
    static let questNameLimit = 10
    /// Characters the topic editor ID keeps once the pair is too long to
    /// spell out.
    static let topicNameLimit = 15
    /// Characters the two editor IDs may occupy together, underscore excluded,
    /// before either is shortened at all.
    static let combinedNameBudget = questNameLimit + topicNameLimit

    /// The `<quest>_<topic>` stem, lowercased because every path here is a
    /// canonical VFS key.
    ///
    /// The two names share a 25-character budget, and the quest is served
    /// first against a topic that has reserved at most its own 15. A quest
    /// that fits what is left is spelled out in full — which is how an
    /// eleven-character quest survives beside a fourteen-character topic, and
    /// how a seventeen-character quest survives beside no topic at all. A
    /// quest that does not fit drops to ten flat rather than being clipped to
    /// the remainder. The topic then takes whatever the quest left, so a
    /// four-character quest is followed by twenty-one characters of topic.
    ///
    /// Either name may be empty — many vanilla topics carry no editor ID,
    /// which is why so many voice files have a doubled underscore.
    static func stem(quest: String?, topic: String?) -> String {
        let quest = (quest ?? "").lowercased()
        let topic = (topic ?? "").lowercased()
        let reserved = min(topic.count, topicNameLimit)
        let questLength = quest.count <= combinedNameBudget - reserved
            ? quest.count
            : questNameLimit
        let topicLength = min(topic.count, combinedNameBudget - questLength)
        return "\(quest.prefix(questLength))_\(topic.prefix(topicLength))"
    }

    /// Everything a voice file's name is built from, as one value: the four
    /// pieces travel together everywhere and a parameter list of them is past
    /// the lint cap.
    ///
    /// - Parameters:
    ///   - objectID: the INFO's FormID as the exporting plugin numbered it —
    ///     see `exportedFormID(_:masterCount:)`.
    ///   - responseNumber: TRDT's response number, one-based, which is the
    ///     trailing `_1`, `_2` of a multi-part line.
    nonisolated struct Name: Equatable {
        let quest: String?
        let topic: String?
        let objectID: UInt32
        let responseNumber: Int
    }

    /// One voice file's name, without a directory.
    static func fileName(_ name: Name) -> String {
        let identifier = String(format: "%08x", name.objectID)
        let stem = stem(quest: name.quest, topic: name.topic)
        return "\(stem)_\(identifier)_\(name.responseNumber).fuz"
    }

    /// Full canonical VFS key for one line.
    static func path(plugin: String, voiceType: String, name: Name) -> String {
        directory(plugin: plugin, voiceType: voiceType) + "\\" + fileName(name)
    }

    /// Directory holding every line one voice type says for one plugin.
    static func directory(plugin: String, voiceType: String) -> String {
        "\(root)\\\(plugin.lowercased())\\\(voiceType.lowercased())"
    }

    /// The FormID as it appears in a voice file name.
    ///
    /// The Creation Kit exports names before it knows where the plugin it is
    /// editing will sit in a load order, so the record's own plugin index is
    /// written as zero and a master's index is written as its position in the
    /// master list. Records the plugin defines carry index `masterCount`, so
    /// that index — and only that index — is cleared. This is why every
    /// Dawnguard line is `00xxxxxx` while the handful that override an
    /// Update.esm record keep their `01`.
    static func exportedFormID(_ id: FormID, masterCount: Int) -> UInt32 {
        id.masterIndex >= masterCount ? id.objectID : id.rawValue
    }
}
