// List and text plumbing for the dialogue menu (issue #205). Satellite of
// UI/DialogueMenuMovieBridge.swift, which holds the measured contract.
//
// Same degradation rule as every other movie bridge: a list the movie has not
// built, a row that is not an object, a text field that is not there — each
// answers nil or does nothing. A vanilla movie whose shape moved must leave an
// entry in the missing-API tally and an empty readout, never take the app down.
//
// Publishing goes through the movie's own entry points where it has them and
// falls back to writing `EntriesA` directly where it does not. Both are here
// rather than one or the other because they answer different questions: the
// entry point is what the vanilla host calls and therefore what keeps the
// menu's own state machine and animations in step, while the array write is
// what a bring-up gate reads back to prove the rows arrived.

import Foundation

nonisolated extension DialogueMenuMovieBridge {
    // MARK: - Writing

    /// Pushes the whole model into the movie: speaker, topic rows, selection,
    /// and whatever line is being said.
    ///
    /// Order matters and follows the journal's measured one: `InvalidateData`
    /// rebuilds the entry clips from the array and resets `iSelectedIndex` to
    /// the base's -1 sentinel as it goes, so the selection is written
    /// afterwards, never before.
    static func publish(_ model: DialogueMenuModel, runtime: SWFMovieRuntime) {
        setSpeakerName(model.speaker, runtime: runtime)
        publishTopics(model, runtime: runtime)
        publishLine(model, runtime: runtime)
        setMenuState(model.state, runtime: runtime)
    }

    /// Writes the movie's own state field to match the engine's.
    ///
    /// The vanilla host owns this field — `DialogueMenuObj` publishes a
    /// `menuState` property over it and the movie's `handleInput` branches on
    /// it — and measurement shows the entry points do not set it themselves:
    /// `swf dialogue-menu --speak` reports `eMenuState` still on
    /// `TOPIC_LIST_SHOWN` after `ShowDialogueText` has put the line in the
    /// field. Routing key input into a movie whose state field disagreed with
    /// what is on screen is exactly how a menu starts answering the wrong key,
    /// so the engine writes it.
    ///
    /// The value comes off the movie's own class constants rather than from a
    /// number pinned here, so a movie whose vocabulary moved is a no-op rather
    /// than a wrong state.
    static func setMenuState(_ state: DialogueMenuModel.State, runtime: SWFMovieRuntime) {
        guard
            let value = stateConstant(constantName(for: state), runtime: runtime),
            let menu = runtime.node(atPath: menuPath, from: runtime.root)
        else {
            return
        }
        menu.object.assign(.integer(value), for: menuStateName)
        runtime.markDirty()
    }

    /// The movie's own name for one engine state.
    static func constantName(for state: DialogueMenuModel.State) -> String {
        switch state {
        case .greeting: "SHOW_GREETING"
        case .topicList: "TOPIC_LIST_SHOWN"
        case .response: "TOPIC_CLICKED"
        }
    }

    /// The topic rows and the selection.
    static func publishTopics(_ model: DialogueMenuModel, runtime: SWFMovieRuntime) {
        let rows = model.topics.enumerated().map { index, entry in
            topicRow(entry, index: index)
        }
        publish(rows: rows, atPath: topicListPath, runtime: runtime)
        // Called after the array write and with no arguments. What the vanilla
        // host passes it is not measured — the movie's function bodies are not
        // readable through the runtime — so the array the list base reads is
        // written first and this is invoked for whatever else it does to the
        // menu around the list. Measured outcome: the rows arrive, and the
        // movie faults on nothing and leaves no unhandled invoke.
        runtime.callMovie("PopulateDialogueLists", atPath: menuPath, arguments: [])
        if rows.isEmpty {
            runtime.callMovie(clearMethod, atPath: topicListPath, arguments: [])
        }
        runtime.callMovie(invalidateMethod, atPath: topicListPath, arguments: [])
        runtime.callMovie(updateListMethod, atPath: topicListPath, arguments: [])
        select(
            model.acceptsSelection ? model.selectedIndex : -1,
            count: rows.count,
            runtime: runtime
        )
    }

    /// The subtitle field, and the movie's own show/hide around it.
    ///
    /// A menu with a line to say shows it; a menu with none hides it and hands
    /// the list back. Both go through the movie's entry points, so its own
    /// transition between the two runs rather than being skipped by writing the
    /// field directly. The rows stay listed behind a line either way — what
    /// stops a second choice landing on top of the first is the selection,
    /// which `publishTopics` writes as -1 while a response is being said.
    static func publishLine(_ model: DialogueMenuModel, runtime: SWFMovieRuntime) {
        guard let line = model.line else {
            setSubtitle(nil, runtime: runtime)
            runtime.callMovie("ShowDialogueList", atPath: menuPath, arguments: [])
            return
        }
        setSubtitle(line.text, runtime: runtime)
    }

    /// Writes the subtitle field and drives the movie's show/hide around it.
    static func setSubtitle(_ text: String?, runtime: SWFMovieRuntime) {
        guard let text, !text.isEmpty else {
            setText("", atPath: subtitleTextPath, runtime: runtime)
            runtime.callMovie("HideDialogueText", atPath: menuPath, arguments: [])
            return
        }
        setText(text, atPath: subtitleTextPath, runtime: runtime)
        runtime.callMovie(
            "ShowDialogueText", atPath: menuPath, arguments: [.string(text)]
        )
    }

    static func setSpeakerName(_ name: String, runtime: SWFMovieRuntime) {
        setText(name, atPath: speakerNamePath, runtime: runtime)
        runtime.callMovie(
            "SetSpeakerName", atPath: menuPath, arguments: [.string(name)]
        )
    }

    /// Replaces the topic list's `EntriesA` with `rows`.
    static func publish(
        rows: [[String: AS2Value]],
        atPath path: String,
        runtime: SWFMovieRuntime
    ) {
        guard let list = runtime.node(atPath: path, from: runtime.root) else { return }
        let entries = runtime.runtime.makeArray(
            rows.map { fields in
                let row = runtime.runtime.makeObject()
                // Sorted so two publishes of equal rows build identical
                // objects, which is what makes a published list comparable.
                for name in fields.keys.sorted() {
                    row.assign(fields[name] ?? .undefined, for: name)
                }
                return .object(row)
            }
        )
        list.object.assign(.object(entries), for: entryArrayName)
    }

    /// Points the list at `index`, or at nothing when `index` is negative.
    ///
    /// Written onto `iSelectedIndex` and followed by `UpdateList`, which is what
    /// repositions the centred entry clips around the new selection.
    /// `TopicList.SetSelectedTopic` was measured and deliberately not used:
    /// `swf dialogue-menu --down 2` reports the movie back at row 0 when that
    /// method is called with the row index and at row 2 when it is not, so
    /// whatever it takes, it is not the index — and calling it would silently
    /// undo the selection the engine just made.
    static func select(_ index: Int, count: Int, runtime: SWFMovieRuntime) {
        guard let list = runtime.node(atPath: topicListPath, from: runtime.root) else {
            return
        }
        let clamped = count > 0 && index >= 0 ? min(index, count - 1) : -1
        list.object.assign(.integer(clamped), for: selectedIndexName)
        guard clamped >= 0 else { return }
        runtime.callMovie(updateListMethod, atPath: topicListPath, arguments: [])
    }

    // MARK: - Rows

    /// One topic row.
    ///
    /// The four field names are the ones `swf action-sweep --movie
    /// dialoguemenu.swf` resolves off the rows the movie is handed: `text` is
    /// what the entry clip draws, `topicIndex` is the row's own position that
    /// a movie-driven selection reports back, `topicIsNew` drives the
    /// never-heard marker, and `responseHash` is the identity the vanilla host
    /// uses to name the chosen response.
    ///
    /// `topicIsNew` is published false rather than guessed: OpenSky does not
    /// model whether the player has heard a topic before. Said-state is per
    /// INFO (`DialogueRuntimeState`), which is not the same question — a topic
    /// whose winning response changed is not a topic the player has not seen.
    /// `responseHash` carries the winning INFO's FormID, which is the identity
    /// OpenSky actually addresses a response by.
    static func topicRow(_ entry: DialogueTopicEntry, index: Int) -> [String: AS2Value] {
        [
            "text": .string(entry.text),
            "topicIndex": .integer(index),
            "topicIsNew": .boolean(false),
            "responseHash": .number(Double(entry.info.rawValue))
        ]
    }

    // MARK: - Reading

    /// Row `text` values in numeric row order.
    ///
    /// `EntriesA` is an AS2 array, so its rows are numeric property names and
    /// have to be sorted numerically — lexical order puts row 10 before row 2.
    static func topicLabels(runtime: SWFMovieRuntime) -> [String] {
        guard
            let list = runtime.node(atPath: topicListPath, from: runtime.root),
            let entries = list.object.lookup(entryArrayName)?.property.value.objectValue
        else {
            return []
        }
        return entries.ownPropertyNames
            .compactMap { name in Int(name).map { ($0, name) } }
            .sorted { $0.0 < $1.0 }
            .compactMap { _, name in
                guard
                    let row = entries.lookup(name)?.property.value.objectValue,
                    case let .string(text) = row.lookup("text")?.property.value
                else {
                    return nil
                }
                return text
            }
    }

    /// The row the movie has selected, or nil when it has none.
    static func selectedIndex(runtime: SWFMovieRuntime) -> Int? {
        guard
            let list = runtime.node(atPath: topicListPath, from: runtime.root),
            case let .number(index) = list.object.lookup(selectedIndexName)?.property.value,
            index.isFinite, index >= 0
        else {
            return nil
        }
        return Int(index)
    }

    /// Text the movie's own subtitle field holds, which is what proves a
    /// publish reached the movie rather than only the engine model.
    static func subtitleText(runtime: SWFMovieRuntime) -> String? {
        text(atPath: subtitleTextPath, runtime: runtime)
    }

    static func speakerNameText(runtime: SWFMovieRuntime) -> String? {
        text(atPath: speakerNamePath, runtime: runtime)
    }

    /// Frame label the topic list holder is stopped on, which is the movie's
    /// own account of the transition it last played.
    static func holderFrameLabel(runtime: SWFMovieRuntime) -> String? {
        guard
            let holder = runtime.node(atPath: topicListHolderPath, from: runtime.root),
            let frames = holder.timeline?.frames,
            frames.indices.contains(holder.currentFrame)
        else {
            return nil
        }
        return frames[holder.currentFrame].label
    }

    // MARK: - Text fields

    private static func setText(_ text: String, atPath path: String, runtime: SWFMovieRuntime) {
        guard let node = runtime.node(atPath: path, from: runtime.root) else { return }
        runtime.setText(text, of: node)
    }

    private static func text(atPath path: String, runtime: SWFMovieRuntime) -> String? {
        guard let node = runtime.node(atPath: path, from: runtime.root) else { return nil }
        // A field's string is a display *member*, not an entry in the node's
        // property table, so it is read through the runtime rather than off
        // `node.object` the way a list's `EntriesA` is.
        return runtime.text(of: node)
    }
}
