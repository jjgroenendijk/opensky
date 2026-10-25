// Dialogue selection against the user's install. The speaker is Sybille Stentor,
// whose own branch topics and two shared ones pass their quests' dialogue
// conditions under the plugin baseline quest state. The pinned numbers detect drift;
// the branch rules behind them are in docs/engine/dialogue.md.
// Assertions are counts, editor IDs, and FormIDs.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyDialogue
@testable import OpenSkyDialogueInterface
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuestsInterface
@testable import OpenSkyWorldConditions
@testable import OpenSkyWorldState
import Testing

struct DialogueRuntimeRealDataTests {
    /// Offers observed on 2026-10-17 against the shipped `Skyrim.esm`. Branches
    /// scope the list: only top-level branch starting topics open a conversation.
    private static let expectedOfferCount = 4
    /// The whole list, by editor ID.
    private static let expectedTopics = [
        "MG01InitialBranchTopic",
        "DialogueSolitudeSybilleBranchTopic",
        "DialogueSolitudeSybille02Topic01",
        "OffersTrainingTopic"
    ]
    /// The greeting topic she opens with under the same state. Its responses are
    /// a random group, so which one wins moves when an update reorders them.
    private static let expectedGreetingTopic: UInt32 = 0x0001_42B5

    @MainActor
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func selectsADeterministicTopicListForOneSpeaker() throws {
        let world = try Self.world()
        let selection = world.runtime.topics(for: Self.speakerKey)
        #expect(selection.offers.count == Self.expectedOfferCount, "offered topic drift")
        let editorIDs = Set(selection.offers.compactMap {
            world.dialogue.topic($0.topic)?.editorID
        })
        for expected in Self.expectedTopics {
            #expect(editorIDs.contains(expected), "missing topic \(expected)")
        }

        // Every offer names a response that really is the first passing one in
        // its topic's file order, which is the selection rule the whole layer
        // rests on.
        for offer in selection.offers {
            let infos = world.dialogue.infos(for: offer.topic)
            let found = offer.considered.first { $0.isWinner }
            let winner = try #require(found)
            #expect(winner.info == offer.info)
            let position = infos.firstIndex { $0.formID == offer.info }
            let winnerIndex = try #require(position)
            #expect(offer.considered.prefix(winnerIndex).allSatisfy { !$0.isWinner })
        }

        // Selection is a pure read: asking twice gives the same answer.
        #expect(world.runtime.topics(for: Self.speakerKey).offers.map(\.topic)
            == selection.offers.map(\.topic))
    }

    /// The greeting she opens with, selected by HELO subtype under the same
    /// fixed quest state.
    @MainActor
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func selectsADeterministicGreeting() throws {
        let world = try Self.world()
        let greeting = try #require(world.runtime.greeting(for: Self.speakerKey))
        #expect(greeting.topic.rawValue == Self.expectedGreetingTopic)
        // The first response of the random group, because the test fixes the pick.
        let first = greeting.considered.first { $0.isWinner || $0.rejection == .lostRandomPick }
        #expect(first?.info == greeting.info)
        #expect(world.runtime.greeting(for: Self.speakerKey)?.info == greeting.info)
    }

    /// Choosing a response records it, and a say-once response then drops out
    /// of the list it was offered in. Driven against real records rather than
    /// synthetic ones, because the say-once flag has to come off the disk.
    @MainActor
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func choosingASayOnceResponseSpendsIt() throws {
        let world = try Self.world()
        let selection = world.runtime.topics(for: Self.speakerKey)
        let sayOnce = selection.offers.first {
            world.dialogue.info($0.info)?.flags.contains(.sayOnce) == true
        }
        guard let sayOnce else {
            // Vanilla may offer this speaker no say-once line under the
            // baseline state; that is data, not a failure.
            return
        }
        try world.runtime.choose(sayOnce.info, speaker: Self.speakerKey)
        #expect(world.runtime.hasBeenSaid(sayOnce.info))
        let after = world.runtime.topics(for: Self.speakerKey)
        #expect(after.offers.first { $0.topic == sayOnce.topic }?.info != sayOnce.info)
    }

    /// Condition-function coverage over exactly the conditions this speaker's
    /// selection evaluates, written to a gitignored run directory so the
    /// documented tally has a source.
    @MainActor
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func recordsConditionCoverageForTheSelection() throws {
        let world = try Self.world()
        let tally = world.runtime.topics(for: Self.speakerKey).tally
        #expect(tally.conditionsEvaluated > 0)

        let report = ([
            "[INFO] conditions:\(tally.conditionsEvaluated) lists:\(tally.listsEvaluated)",
            "[INFO] failures:\(tally.failureTotal)"
        ] + tally.rankedUnknownFunctions().prefix(20).map {
            "[INFO] unimplemented \($0.name): \($0.count)"
        }).joined(separator: "\n") + "\n"
        print(report)
        try Self.writeReport(report)
    }

    // MARK: - Private

    private struct World {
        let dialogue: DialogueStore
        let runtime: DialogueRuntime
    }

    /// `Skyrim.esm`'s Sybille Stentor NPC_ record.
    private static let speaker = DialogueSpeakerContext(base: 0x0001_32AA)

    private static var speakerKey: ReferenceKey {
        speaker.speakerKey
    }

    @MainActor
    private static func world() throws -> World {
        let root = try #require(RealDataEnvironment.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let localized = try file.pluginHeader().isLocalized
        let dialogue = DialogueStore(
            file: file, pluginName: "Skyrim.esm", localized: localized
        )
        let quests = QuestStore(file: file, pluginName: "Skyrim.esm")
        var runtime = try DialogueRuntime(
            store: WorldStateStore(),
            dialogue: dialogue,
            questStates: QuestResolution(defaults: quests),
            context: speaker.context(root: root, file: file),
            registry: .standard
        )
        runtime.randomPick = { _ in 0 }
        return World(dialogue: dialogue, runtime: runtime)
    }

    private static func writeReport(_ report: String) throws {
        let root = try RepositoryLogs.directory("dialogue-selection")
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let run = root.appending(path: stamp, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        try report.write(
            to: run.appending(path: "report.txt"), atomically: true, encoding: .utf8
        )
        print("[INFO] dialogue selection report: \(run.path())")
    }
}
