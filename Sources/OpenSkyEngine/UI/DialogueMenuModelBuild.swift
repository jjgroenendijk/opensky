// Builds a `DialogueMenuModel` out of live dialogue state (issue #205).
// Satellite of UI/DialogueMenuModel.swift, which holds the value types.
//
// Two text questions decide what the menu reads, and both are record facts
// rather than conventions invented here:
//
// * A topic row shows the winning INFO's RNAM when it has one and the parent
//   DIAL's FULL otherwise. UESP's INFO page states the override in those terms:
//   RNAM is "the player's response to a question (INFO with TCLT options). If
//   present, overrides the default text coming from the parent dialogue topic"
//   (<https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/INFO>). Our decoder
//   calls that field `prompt`.
// * The line a speaker says is the INFO's TRDT response text, which
//   `TopicInfo.Response.resolvedText(using:)` already pins to `.ilstrings` —
//   the table whose name says what it holds.
//
// Which table each answers out of is measured rather than assumed:
// `openskycli swf dialogue-menu --text` resolves every field out of all three
// tables and prints what each answered, the same instrument
// `swf quest-journal --text` is for the journal. On vanilla `Skyrim.esm` the
// DIAL FULL and the INFO RNAM answer out of `.strings` and the response text
// out of `.ilstrings`.
//
// Documented in docs/engine/dialogue-menu.md.

import Foundation

nonisolated extension DialogueMenuModel {
    /// What one topic row reads, in the order the records decide it.
    ///
    /// Never empty: an unlabelled row cannot be chosen on purpose, so a topic
    /// whose text resolves to nothing falls back to its editor ID and then to
    /// its FormID.
    static func rowText(
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

    /// Every TRDT run of one response, in file order, resolved.
    ///
    /// A run whose text does not resolve becomes an empty string rather than
    /// being dropped, because the runs are also the count a readout reports and
    /// silently shortening a three-line response to two would misreport it.
    static func responseRuns(_ info: TopicInfo, strings: LocalizedStrings?) -> [String] {
        info.responses.map { text($0.text, kind: .ilstrings, strings: strings) ?? "" }
    }

    /// Resolves one lstring, with or without string tables.
    ///
    /// A plugin whose header does not say localized writes its text inline, and
    /// then there is no table to consult and none is needed. Same helper shape
    /// as `JournalMenuModel.text(_:kind:strings:)`, and deliberately a second
    /// copy rather than a shared one: the two menus resolve different fields
    /// out of different tables, and a shared entry point would invite passing
    /// the wrong kind.
    static func text(
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
    static func rows(
        _ selection: DialogueSelection,
        runtime: DialogueRuntime,
        strings: LocalizedStrings?
    ) -> [DialogueTopicEntry] {
        selection.offers.compactMap { offer in
            guard let topic = runtime.dialogue.topic(offer.topic) else { return nil }
            let info = runtime.dialogue.info(offer.info)
            return DialogueTopicEntry(
                topic: offer.topic,
                info: offer.info,
                text: rowText(topic: topic, info: info, strings: strings),
                endsConversation: info?.flags.contains(.goodbye) ?? false
            )
        }
    }

    /// One conversation as it opens: the speaker's offered topics, and the
    /// greeting they lead with when they have one.
    ///
    /// The greeting is a HELO topic's winning response rather than a fourth
    /// kind of thing, which is what `DialogueRuntime.greeting(for:)` answers.
    /// A speaker with no greeting opens straight on the list, which is also
    /// what a speaker with no topics at all does — the menu then shows an empty
    /// list and says so rather than refusing to open.
    static func build(
        speaker: ReferenceKey,
        name: String,
        runtime: DialogueRuntime,
        strings: LocalizedStrings?
    ) -> DialogueMenuModel {
        var model = DialogueMenuModel(
            speaker: name.isEmpty ? speaker.description : name,
            speakerKey: speaker,
            topics: rows(runtime.topics(for: speaker), runtime: runtime, strings: strings)
        )
        if
            let greeting = runtime.greeting(for: speaker),
            let info = runtime.dialogue.info(greeting.info)
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
