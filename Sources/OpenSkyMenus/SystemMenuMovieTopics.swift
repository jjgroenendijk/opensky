// The System page's Help and Installed Content rows. The movie asks for the topic
// list and checks it at once, so these calls are answered inside the call, not queued.

import Foundation
import OpenSkyFormatsSWF

nonisolated extension SystemMenuMovieBridge {
    /// The calls each topic page makes, measured from `SystemPage.onCategoryButtonPress`.
    public struct TopicCalls: Equatable, Sendable {
        public let page: SystemMenuPage
        /// `([entryList])`: fill the list; the movie then sorts it and shows it if not empty.
        public let populate: String
        /// `([entry.index, titleField, textField])`: write the topic into the two fields.
        public let requestText: String
    }

    public static let topicCalls = [
        TopicCalls(page: .help, populate: "PopulateHelpTopics", requestText: "RequestHelpText"),
        TopicCalls(
            page: .installedContent, populate: "PopulateCreationClubTopics",
            requestText: "RequestCreationClubText"
        )
    ]

    /// `topics` shows the page and returns its rows; `open` opens a row and returns it.
    /// Only those values cross to the main actor; the movie is written here, inside the call.
    public static func registerTopics(
        runtime: SWFMovieRuntime,
        topics: @escaping @MainActor @Sendable (SystemMenuPage) -> [SystemMenuTopic],
        open: @escaping @MainActor @Sendable (Int) -> SystemMenuTopic?
    ) {
        for calls in topicCalls {
            runtime.registerHostFunction(calls.populate) { call in
                let rows = topicRows(MainActor.assumeIsolated { topics(calls.page) })
                TitleMenuLoadBridge.fill(rows, list: call.arguments.first, runtime: call.movie)
                return .undefined
            }
            runtime.registerHostFunction(calls.requestText) { call in
                guard
                    let index = TitleMenuLoadBridge.index(call.arguments),
                    let topic = MainActor.assumeIsolated({ open(index) })
                else { return .undefined }
                writeTopic(topic, arguments: call.arguments, runtime: call.movie)
                return .undefined
            }
        }
    }

    /// The movie's highlighted row on a topic page. `SystemPage` keeps each list as a member.
    public static func selectedTopicRow(
        _ page: SystemMenuPage, runtime: SWFMovieRuntime
    ) -> Int? {
        let member = page == .help ? "HelpList" : "CreationsList"
        guard
            let systemPage = runtime.node(atPath: systemPagePath, from: runtime.root),
            let list = systemPage.object.lookup(member)?.property.value.objectValue,
            case let .number(selected) = list.lookup("iSelectedIndex")?.property.value,
            selected.isFinite, selected >= 0
        else { return nil }
        return Int(selected)
    }

    /// Writes the topic into the title and text fields a text request passed.
    public static func writeTopic(
        _ topic: SystemMenuTopic, arguments: [AS2Value], runtime: SWFMovieRuntime
    ) {
        let fields = arguments.dropFirst()
        writeText(topic.title, to: fields.first, runtime: runtime)
        writeText(topic.text, to: fields.dropFirst().first, runtime: runtime)
    }

    /// One entry per topic. `index` is what the movie hands back after it sorts the list.
    public static func topicRows(_ topics: [SystemMenuTopic]) -> [[String: AS2Value]] {
        topics.enumerated().map { index, topic in
            ["text": .string(topic.title), "index": .integer(index)]
        }
    }

    /// A text field, or a CLIK component. A component redraws its `textField` from its own
    /// `text`, so the text goes through that setter.
    static func writeText(_ text: String, to value: AS2Value?, runtime: SWFMovieRuntime) {
        guard let object = value?.objectValue else { return }
        if let setter = object.lookup("text")?.property.setter {
            runtime.markDirty()
            runtime.runtime.invoke(.object(setter), thisValue: .object(object), arguments: [
                .string(text)
            ])
        } else if let field = SWFDisplayObject.resolve(object) {
            runtime.setText(text, of: field)
        }
    }
}
