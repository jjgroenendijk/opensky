// Engine-side model of one conversation: the listed topics, the chosen one,
// and the line said back. `DialogueMenuMovieBridge` pushes it into
// `dialoguemenu.swf`; `DialogueRuntime` decides which topics are offered. The
// movie's `DialogueMenuObj` has four states; this models the three the engine
// needs and leaves `TRANSITIONING` to the movie's animation
// (docs/engine/dialogue-menu.md).

import Foundation
import OpenSkyFormatsESM

/// One selectable line in the topic list.
nonisolated public struct DialogueTopicEntry: Equatable, Sendable {
    /// The INFO that won this topic's selection, which is what choosing the row
    /// delivers.
    public let info: FormID
    /// What the row reads. Never empty: a topic whose text resolves to nothing
    /// falls back to its editor ID and then to its FormID, because an unlabelled
    /// row cannot be chosen on purpose.
    public let text: String
    /// Whether the winning response ends the conversation, so a goodbye row can
    /// be told apart from one that leads on without choosing it first.
    public let endsConversation: Bool

    public init(info: FormID, text: String, endsConversation: Bool) {
        self.info = info
        self.text = text
        self.endsConversation = endsConversation
    }
}

/// The line a speaker is currently delivering.
nonisolated public struct DialogueResponseLine: Equatable, Sendable {
    /// The INFO the line came from.
    public let info: FormID
    /// One TRDT response run's text, resolved. Empty is possible and is not an
    /// error: an INFO can carry a response with no text, and the subtitle then
    /// shows nothing while the rest of the flow still advances.
    public let text: String
    /// Position of this run inside the response, and how many there are, so a
    /// readout can say "2 of 3" without recomputing it.
    public let index: Int
    public let count: Int

    /// Whether another run follows in the same response.
    public var hasMore: Bool {
        index + 1 < count
    }
}

/// Rows, cursor and playback state of one open conversation.
nonisolated public struct DialogueMenuModel: Equatable, Sendable {
    /// Which half of the menu the player is looking at.
    public enum State: Equatable, Sendable {
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
    public let speaker: String
    /// The speaker's session-stable identity, which every mutation this model
    /// drives is filed under.
    public let speakerKey: ReferenceKey?
    /// Topics on offer, in `DialogueRuntime`'s own order: descending DIAL
    /// priority, then ascending FormID.
    public private(set) var topics: [DialogueTopicEntry]
    /// Row index into `topics`, or -1 when there is nothing to select. -1 is
    /// the list base's own nothing-selected sentinel, measured on
    /// `iSelectedIndex` and shared with every other CLIK list in the game.
    public private(set) var selectedIndex: Int
    public private(set) var state: State
    /// The run being said, or nil when nothing is.
    public private(set) var line: DialogueResponseLine?
    /// Every run of the response being said, so advancing is a cursor move
    /// rather than a second lookup into the store.
    private var runs: [String] = []

    public static let empty = DialogueMenuModel(speaker: "", speakerKey: nil, topics: [])

    public init(
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

    public var selectedTopic: DialogueTopicEntry? {
        topics.indices.contains(selectedIndex) ? topics[selectedIndex] : nil
    }

    /// True when the speaker has nothing to offer, which is the one case the
    /// menu shows a line and no list.
    public var isEmpty: Bool {
        topics.isEmpty
    }

    /// Whether the topic list takes input right now. False while a line is
    /// being said, which is what stops a second choice landing on top of the
    /// first.
    public var acceptsSelection: Bool {
        state == .topicList && !topics.isEmpty
    }

    /// The subtitle the HUD should be showing, or nil when it should show
    /// none.
    public var subtitle: String? {
        guard let line, !line.text.isEmpty else { return nil }
        return line.text
    }

    // MARK: - Cursor

    /// Points the list at one row, clamped. An empty list stays at -1.
    public mutating func select(_ index: Int) {
        selectedIndex = topics.isEmpty ? -1 : min(max(index, 0), topics.count - 1)
    }

    /// Moves the selection by `delta` rows without wrapping, matching the list
    /// base's own `moveSelectionUp`/`moveSelectionDown`, which stop at the ends.
    public mutating func moveSelection(by delta: Int) {
        guard !topics.isEmpty else { return }
        select(selectedIndex + delta)
    }

    // MARK: - Playback

    /// Starts saying one response, whichever state the menu was in.
    ///
    /// - Parameter runs: the response's TRDT runs in file order. An empty array
    ///   still enters the speaking state with no line, because a response that
    ///   carries no text is a response that was said.
    public mutating func beginResponse(info: FormID, runs: [String], isGreeting: Bool = false) {
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
    public mutating func advanceResponse() -> Bool {
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
    public mutating func showTopicList() {
        state = .topicList
        line = nil
        runs = []
        select(selectedIndex)
    }

    /// Replaces the offered topics, which is what a chosen response's follow-up
    /// links produce. The cursor returns to the top, because the rows under it
    /// are not the rows it was pointing at.
    public mutating func setTopics(_ entries: [DialogueTopicEntry]) {
        topics = entries
        select(0)
    }
}
