// List and text plumbing for the dialogue menu. The measured contract is in
// DialogueMenuMovieBridge.swift. A missing list, row, or field is skipped, never
// thrown. Rows go through the movie's own entry points, which keep its state
// machine in step, and are also written to `EntriesA`, which a gate reads back.

import Foundation
import OpenSkyFormatsESM
import OpenSkyFormatsSWF

nonisolated extension DialogueMenuMovieBridge {
    // MARK: - Writing

    /// Pushes the whole model into the movie. `InvalidateData` resets
    /// `iSelectedIndex` to -1, so the selection is written after it.
    public static func publish(_ model: DialogueMenuModel, runtime: SWFMovieRuntime) {
        setSpeakerName(model.speaker, runtime: runtime)
        publishTopics(model, runtime: runtime)
        publishLine(model, runtime: runtime)
        setMenuState(model.state, runtime: runtime)
    }

    /// Writes the movie's state field to match the engine. The entry points do
    /// not set it themselves (measured with `swf dialogue-menu --speak`), and a
    /// stale state makes the menu answer the wrong key. The value comes from the
    /// movie's own class constants, so a changed movie makes this a no-op.
    public static func setMenuState(_ state: DialogueMenuModel.State, runtime: SWFMovieRuntime) {
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
    public static func constantName(for state: DialogueMenuModel.State) -> String {
        switch state {
        case .greeting: "SHOW_GREETING"
        case .topicList: "TOPIC_LIST_SHOWN"
        case .response: "TOPIC_CLICKED"
        }
    }

    /// The topic rows and the selection.
    public static func publishTopics(_ model: DialogueMenuModel, runtime: SWFMovieRuntime) {
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

    /// Shows the line being said, or hides the subtitle and returns to the list.
    /// Both go through the movie's entry points so its own transition runs.
    public static func publishLine(_ model: DialogueMenuModel, runtime: SWFMovieRuntime) {
        guard let line = model.line else {
            setSubtitle(nil, runtime: runtime)
            runtime.callMovie("ShowDialogueList", atPath: menuPath, arguments: [])
            return
        }
        setSubtitle(line.text, runtime: runtime)
    }

    /// Writes the subtitle field and drives the movie's show/hide around it.
    public static func setSubtitle(_ text: String?, runtime: SWFMovieRuntime) {
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

    public static func setSpeakerName(_ name: String, runtime: SWFMovieRuntime) {
        setText(name, atPath: speakerNamePath, runtime: runtime)
        runtime.callMovie(
            "SetSpeakerName", atPath: menuPath, arguments: [.string(name)]
        )
    }

    /// Replaces the topic list's `EntriesA` with `rows`.
    public static func publish(
        rows: [[String: AS2Value]],
        atPath path: String,
        runtime: SWFMovieRuntime
    ) {
        MenuMovieEntryList.publish(rows, atPath: path, runtime: runtime)
    }

    /// Points the list at `index`, or at nothing when `index` is negative, then
    /// calls `UpdateList`. `TopicList.SetSelectedTopic` does not take the row
    /// index (measured with `swf dialogue-menu --down 2`), so it is not used.
    public static func select(_ index: Int, count: Int, runtime: SWFMovieRuntime) {
        guard let list = runtime.node(atPath: topicListPath, from: runtime.root) else {
            return
        }
        let clamped = count > 0 && index >= 0 ? min(index, count - 1) : -1
        list.object.assign(.integer(clamped), for: selectedIndexName)
        guard clamped >= 0 else { return }
        runtime.callMovie(updateListMethod, atPath: topicListPath, arguments: [])
    }

    // MARK: - Rows

    /// One topic row, with the field names `swf action-sweep` reads off the movie.
    /// `topicIsNew` is false because OpenSky does not track heard topics, and
    /// `responseHash` carries the winning INFO's FormID.
    public static func topicRow(_ entry: DialogueTopicEntry, index: Int) -> [String: AS2Value] {
        [
            "text": .string(entry.text),
            "topicIndex": .integer(index),
            "topicIsNew": .boolean(false),
            "responseHash": .number(Double(entry.info.rawValue))
        ]
    }

    // MARK: - Reading

    /// Row `text` values in numeric row order.
    public static func topicLabels(runtime: SWFMovieRuntime) -> [String] {
        MenuMovieEntryList.labels(atPath: topicListPath, runtime: runtime)
    }

    /// The row the movie has selected, or nil when it has none.
    public static func selectedIndex(runtime: SWFMovieRuntime) -> Int? {
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
    public static func subtitleText(runtime: SWFMovieRuntime) -> String? {
        text(atPath: subtitleTextPath, runtime: runtime)
    }

    public static func speakerNameText(runtime: SWFMovieRuntime) -> String? {
        text(atPath: speakerNamePath, runtime: runtime)
    }

    /// Frame label the topic list holder is stopped on, which is the movie's
    /// own account of the transition it last played.
    public static func holderFrameLabel(runtime: SWFMovieRuntime) -> String? {
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
