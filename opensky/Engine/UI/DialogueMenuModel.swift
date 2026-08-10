// Engine-side model of one conversation (issue #205, roadmap item 17.3): the
// topics the player would see listed, the one they picked, and the line being
// said back, independent of any movie.
//
// The same split every other menu in `opensky/Engine/UI/` uses.
// `DialogueMenuModel` is a `nonisolated struct`; `DialogueMenuMovieBridge` is
// what pushes it through the measured `dialoguemenu.swf` contract. Keeping the
// two apart is what lets the panel, the unit suites and the CLI probe assert
// the same rows with no window, no renderer and no install.
//
// Nothing here decides *which* topics are offered. That is #426's
// `DialogueRuntime`, whose `DialogueSelection` this is built from in
// `DialogueMenuModelBuild.swift`; this file is rows, a cursor and a small state
// machine, and it is deliberately testable without a `WorldStateStore`.
//
// ## The state machine, and why it has three states
//
// The movie's own `DialogueMenuObj` carries four: `SHOW_GREETING`,
// `TOPIC_LIST_SHOWN`, `TOPIC_CLICKED` and `TRANSITIONING`, measured off the
// registered class. This models the three that mean something to the engine —
// the greeting being said, the list being read, a response being said — and
// leaves `TRANSITIONING` to the movie, which owns the animation between them.
// Adding a fourth engine state that only ever mirrored an animation frame
// would be a second clock to keep in step with the movie's own.
//
// Documented in docs/engine/dialogue-menu.md.

import Foundation

/// One selectable line in the topic list.
nonisolated struct DialogueTopicEntry: Equatable, Sendable {
    /// The DIAL record the row stands for.
    let topic: FormID
    /// The INFO that won this topic's selection, which is what choosing the row
    /// delivers.
    let info: FormID
    /// What the row reads. Never empty: a topic whose text resolves to nothing
    /// falls back to its editor ID and then to its FormID, because an unlabelled
    /// row cannot be chosen on purpose.
    let text: String
    /// Whether the winning response ends the conversation, so a goodbye row can
    /// be told apart from one that leads on without choosing it first.
    let endsConversation: Bool
}

/// The line a speaker is currently delivering.
nonisolated struct DialogueResponseLine: Equatable, Sendable {
    /// The INFO the line came from.
    let info: FormID
    /// One TRDT response run's text, resolved. Empty is possible and is not an
    /// error: an INFO can carry a response with no text, and the subtitle then
    /// shows nothing while the rest of the flow still advances.
    let text: String
    /// Position of this run inside the response, and how many there are, so a
    /// readout can say "2 of 3" without recomputing it.
    let index: Int
    let count: Int

    /// Whether another run follows in the same response.
    var hasMore: Bool {
        index + 1 < count
    }
}

/// Rows, cursor and playback state of one open conversation.
nonisolated struct DialogueMenuModel: Equatable {
    /// Which half of the menu the player is looking at.
    enum State: Equatable, Sendable {
        /// A greeting is being said before the list appears, which is the
        /// movie's `SHOW_GREETING`.
        case greeting
        /// The topic list is up and takes input.
        case topicList
        /// A chosen response is being said, which is the movie's
        /// `TOPIC_CLICKED`. The list is still built but does not take a
        /// selection.
        case response
    }

    /// Who is speaking. Never empty for the same reason a row's text is not.
    let speaker: String
    /// The speaker's session-stable identity, which every mutation this model
    /// drives is filed under.
    let speakerKey: ReferenceKey?
    /// Topics on offer, in `DialogueRuntime`'s own order: descending DIAL
    /// priority, then ascending FormID.
    private(set) var topics: [DialogueTopicEntry]
    /// Row index into `topics`, or -1 when there is nothing to select. -1 is
    /// the list base's own nothing-selected sentinel, measured on
    /// `iSelectedIndex` and shared with every other CLIK list in the game.
    private(set) var selectedIndex: Int
    private(set) var state: State
    /// The run being said, or nil when nothing is.
    private(set) var line: DialogueResponseLine?
    /// Every run of the response being said, so advancing is a cursor move
    /// rather than a second lookup into the store.
    private var runs: [String] = []

    static let empty = DialogueMenuModel(speaker: "", speakerKey: nil, topics: [])

    init(
        speaker: String,
        speakerKey: ReferenceKey?,
        topics: [DialogueTopicEntry],
        selectedIndex: Int = 0,
        state: State = .topicList
    ) {
        self.speaker = speaker
        self.speakerKey = speakerKey
        self.topics = topics
        self.selectedIndex = topics.isEmpty ? -1 : min(max(selectedIndex, 0), topics.count - 1)
        self.state = state
    }

    var selectedTopic: DialogueTopicEntry? {
        topics.indices.contains(selectedIndex) ? topics[selectedIndex] : nil
    }

    /// True when the speaker has nothing to offer, which is the one case the
    /// menu shows a line and no list.
    var isEmpty: Bool {
        topics.isEmpty
    }

    /// Whether the topic list takes input right now. False while a line is
    /// being said, which is what stops a second choice landing on top of the
    /// first.
    var acceptsSelection: Bool {
        state == .topicList && !topics.isEmpty
    }

    /// The subtitle the HUD should be showing, or nil when it should show
    /// none.
    var subtitle: String? {
        guard let line, !line.text.isEmpty else { return nil }
        return line.text
    }

    // MARK: - Cursor

    /// Points the list at one row, clamped. An empty list stays at -1.
    mutating func select(_ index: Int) {
        selectedIndex = topics.isEmpty ? -1 : min(max(index, 0), topics.count - 1)
    }

    /// Moves the selection by `delta` rows without wrapping, matching the list
    /// base's own `moveSelectionUp`/`moveSelectionDown`, which stop at the ends.
    mutating func moveSelection(by delta: Int) {
        guard !topics.isEmpty else { return }
        select(selectedIndex + delta)
    }

    // MARK: - Playback

    /// Starts saying one response, whichever state the menu was in.
    ///
    /// - Parameter runs: the response's TRDT runs in file order. An empty array
    ///   still enters the speaking state with no line, because a response that
    ///   carries no text is a response that was said.
    mutating func beginResponse(info: FormID, runs: [String], isGreeting: Bool = false) {
        self.runs = runs
        state = isGreeting ? .greeting : .response
        line = DialogueResponseLine(
            info: info, text: runs.first ?? "", index: 0, count: runs.count
        )
    }

    /// Moves to the next run of the response being said.
    ///
    /// - Returns: true when a further run was shown, false when the response
    ///   is finished — which is the caller's cue to hand the list back or to
    ///   end the conversation.
    @discardableResult
    mutating func advanceResponse() -> Bool {
        guard let line, line.hasMore else { return false }
        let next = line.index + 1
        self.line = DialogueResponseLine(
            info: line.info,
            text: runs.indices.contains(next) ? runs[next] : "",
            index: next,
            count: line.count
        )
        return true
    }

    /// Hands the list back after a response, clearing the line the subtitle is
    /// showing.
    mutating func showTopicList() {
        state = .topicList
        line = nil
        runs = []
        select(selectedIndex)
    }

    /// Replaces the offered topics, which is what a chosen response's follow-up
    /// links produce. The cursor returns to the top, because the rows under it
    /// are not the rows it was pointing at.
    mutating func setTopics(_ entries: [DialogueTopicEntry]) {
        topics = entries
        select(0)
    }
}
