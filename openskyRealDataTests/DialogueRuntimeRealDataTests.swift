// Env-gated dialogue selection against the user's read-only vanilla install
// (issue #426, roadmap item 17.2).
//
// One concrete speaker, one fixed quest state, one pinned answer. The speaker
// is Delphine, chosen because the 17.1 sweep found her named by more
// player-facing INFO conditions than any other NPC in `Skyrim.esm` — 165
// responses across 123 topics — so her list exercises the quest gate, file
// order and the condition seam at once rather than one of them.
//
// The quest state is the plugin baseline: nothing has started, so exactly the
// start-game-enabled quests are running. That is what makes the answer
// deterministic without the test having to author a save.
//
// The pinned numbers are drift detection, not a claim that OpenSky reproduces
// the vanilla topic menu. Selection here offers every player-facing topic whose
// quest runs and whose responses pass, while the original engine additionally
// scopes topics to the speaker's active dialogue views; the gap is stated in
// docs/engine/dialogue.md. Registering another condition function legitimately
// changes these numbers, and updating them is part of that change.
//
// No game-derived bytes leave the run: the assertions are counts, editor IDs
// and FormIDs.

import Foundation
@testable import opensky
import Testing

struct DialogueRuntimeRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// `Skyrim.esm`'s Delphine NPC_ record, and the synthetic placement key she
    /// is selected against. The placement is this test's own: selection needs a
    /// `ReferenceKey` with a base form, not a loaded cell.
    private static let delphineBase: UInt32 = 0x0001_3478
    private static let delphineReference: UInt32 = 0x000A_0001

    /// Offers observed on 2026-08-09 against the shipped `Skyrim.esm`.
    private static let expectedOfferCount = 54
    /// Topics that must be in the list, by editor ID: Delphine's own MQ00
    /// conversation, which is hers by `GetIsID` and runs because MQ00 is
    /// start-game-enabled.
    private static let expectedTopics = [
        "MQDelphineConcordat",
        "MQDelphineJusticiars",
        "MQDelphineThalmorLongVersion",
        "MQDelphineThalmorShortVersion",
        "MQThalmorDelphineWhyHunting"
    ]
    /// The greeting she opens with under the same state.
    private static let expectedGreetingTopic: UInt32 = 0x0001_42B5
    private static let expectedGreetingInfo: UInt32 = 0x0008_7940

    @MainActor
    @Test(.enabled(if: Self.dataRoot != nil))
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
    @Test(.enabled(if: Self.dataRoot != nil))
    func selectsADeterministicGreeting() throws {
        let world = try Self.world()
        let greeting = try #require(world.runtime.greeting(for: Self.speakerKey))
        #expect(greeting.topic.rawValue == Self.expectedGreetingTopic)
        #expect(greeting.info.rawValue == Self.expectedGreetingInfo)
    }

    /// Choosing a response records it, and a say-once response then drops out
    /// of the list it was offered in. Driven against real records rather than
    /// synthetic ones, because the say-once flag has to come off the disk.
    @MainActor
    @Test(.enabled(if: Self.dataRoot != nil))
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
    @Test(.enabled(if: Self.dataRoot != nil))
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
        let quests: QuestStore
        let runtime: DialogueRuntime
    }

    private static var speakerKey: ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: delphineReference)
    }

    @MainActor
    private static func world() throws -> World {
        let root = try #require(dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let localized = try file.pluginHeader().isLocalized
        let dialogue = DialogueStore(
            file: file, pluginName: "Skyrim.esm", localized: localized
        )
        let quests = QuestStore(file: file, pluginName: "Skyrim.esm")
        let runtime = try DialogueRuntime(
            store: WorldStateStore(),
            dialogue: dialogue,
            quests: quests,
            questStates: QuestResolution(defaults: quests),
            context: ConditionContext(
                references: ConditionEvaluatorFixture.references([
                    (formID: delphineReference, base: delphineBase)
                ]),
                subject: speakerKey,
                target: .player
            )
        )
        return World(dialogue: dialogue, quests: quests, runtime: runtime)
    }

    private static func writeReport(_ report: String) throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs/dialogue-selection", directoryHint: .isDirectory)
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
