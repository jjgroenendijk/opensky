// Builds a `DialogueMenuModel` out of live dialogue state. A topic row shows
// the winning INFO's RNAM (`prompt`) when present, else the parent DIAL's FULL
// (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INFO>). A spoken line
// is the INFO's TRDT text from `.ilstrings`. The tables were measured with
// `openskycli swf dialogue-menu --text` (docs/engine/dialogue-menu.md).

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated extension DialogueMenuModel {
    /// What one topic row reads, in the order the records decide it.
    ///
    /// Never empty: an unlabelled row cannot be chosen on purpose, so a topic
    /// whose text resolves to nothing falls back to its editor ID and then to
    /// its FormID.
    public static func rowText(
        topic: DialogueTopic,
        info: TopicInfo?,
        strings: LocalizedStrings?
    ) -> String {
        let prompt = text(info?.prompt, kind: .strings, strings: strings)
        if let prompt, !prompt.isEmpty {
            return prompt
        }
        let name = text(topic.name, kind: .strings, strings: strings)
        if let name, !name.isEmpty {
            return name
        }
        if let editorID = topic.editorID, !editorID.isEmpty {
            return editorID
        }
        return topic.formID.description
    }

    /// Every TRDT run of one response, in file order, resolved. Pass the INFO
    /// `DialogueStore.responseSource(ofInfo:)` gives, so a shared line has text.
    ///
    /// A run whose text does not resolve becomes an empty string rather than
    /// being dropped, because the runs are also the count a readout reports and
    /// silently shortening a three-line response to two would misreport it.
    public static func responseRuns(_ info: TopicInfo, strings: LocalizedStrings?) -> [String] {
        info.responses.map { text($0.text, kind: .ilstrings, strings: strings) ?? "" }
    }

    /// Resolves one lstring, with or without string tables; a plugin that is
    /// not localized writes text inline. A separate copy from
    /// `JournalMenuModel.text(_:kind:strings:)`, because the menus read
    /// different fields from different tables.
    public static func text(
        _ value: LString?,
        kind: StringTable.Kind,
        strings: LocalizedStrings?
    ) -> String? {
        if let strings {
            return strings.resolve(value, kind: kind)
        }
        guard case let .inline(inline) = value else { return nil }
        return inline
    }
}

@MainActor
extension DialogueMenuModel {
    /// Every offered topic of one selection as menu rows.
    ///
    /// The selection's order is kept as it arrives: `DialogueRuntime` already
    /// sorts by descending DIAL priority and ascending FormID, and re-sorting
    /// here would be a second ordering rule to keep in step with that one.
    public static func rows(
        _ selection: DialogueSelection,
        runtime: any DialogueAccess,
        strings: LocalizedStrings?
    ) -> [DialogueTopicEntry] {
        selection.offers.compactMap { offer in
            guard let topic = runtime.dialogue.topic(offer.topic) else { return nil }
            let info = runtime.dialogue.info(offer.info)
            return DialogueTopicEntry(
                info: offer.info,
                text: rowText(topic: topic, info: info, strings: strings),
                endsConversation: info?.flags.contains(.goodbye) ?? false
            )
        }
    }

    /// One conversation as it opens: the speaker's offered topics and the
    /// greeting from `DialogueRuntime.greeting(for:)`, if any. A speaker with no
    /// greeting or no topics still opens the menu, which says the list is empty.
    public static func build(
        speaker: ReferenceKey,
        name: String,
        runtime: any DialogueAccess,
        strings: LocalizedStrings?
    ) -> DialogueMenuModel {
        var model = DialogueMenuModel(
            speaker: name.isEmpty ? speaker.description : name,
            speakerKey: speaker,
            topics: rows(runtime.topics(for: speaker), runtime: runtime, strings: strings)
        )
        if
            let greeting = runtime.greeting(for: speaker),
            let info = runtime.dialogue.responseSource(ofInfo: greeting.info)
        {
            model.beginResponse(
                info: greeting.info,
                runs: responseRuns(info, strings: strings),
                isGreeting: true
            )
        }
        return model
    }
}
