// M17 acceptance, vanilla half (issue #209): one conversation with one real
// speaker in the user's own install, from the offered list to the recording on
// disk to the save.
//
// The synthetic gate (`M17AcceptanceTests`) drives the app's own entry points
// over records built in code, which is what makes it deterministic and what
// makes it able to run a Papyrus result script. What it cannot show is that the
// same loop holds over shipped data: 15,037 topics whose conditions were
// written by somebody else, voice file names that have to be re-derived from
// editor IDs rather than read out of a field, and a lip track embedded inside
// the recording it belongs to.
//
// The speaker is Delphine, for the reason `DialogueRuntimeRealDataTests` gives:
// the 17.1 sweep found her named by more player-facing INFO conditions than any
// other NPC in `Skyrim.esm`, so her list exercises the quest gate, file order
// and the condition seam at once.
//
// One deliberate difference from the synthetic gate: the quest stage here is set
// through `QuestRuntime.setStage`, which is the same call a result script's
// `SetStage` native lands on, rather than by running a vanilla result script on
// the Papyrus VM. Running shipped quest scripts is M11's own gate
// (`PapyrusAcceptanceRealDataTests`), and the dialogue-to-fragment-to-stage
// chain is proven end to end on the VM by `PapyrusWorldDialogueTests` and by the
// synthetic M17 route. What this suite adds is that the *state* those calls
// write is the state a real conversation reads back, and that it survives a
// save.
//
// No game-derived bytes leave the run: the assertions are counts, editor IDs,
// FormIDs and derived names, and the report goes to gitignored `logs/`.
//
// Run: make realtest T='M17AcceptanceRealDataTests'

import Foundation
@testable import opensky
import Testing

struct M17AcceptanceRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// `Skyrim.esm`'s Delphine NPC_ record, and the synthetic placement key she
    /// is selected against. The placement is this suite's own: selection needs
    /// a `ReferenceKey` with a base form, not a loaded cell.
    private static let delphineBase: UInt32 = 0x0001_3478
    private static let delphineReference: UInt32 = 0x000A_0001

    /// The whole gate in one run, because every step reads what the one before
    /// it wrote.
    @MainActor
    @Test(.enabled(if: Self.dataRoot != nil))
    func theConversationHoldsAgainstTheUsersOwnInstall() throws {
        let world = try Self.world()
        let selection = try Self.expectAConditionFilteredList(world)
        // The offer this gate can follow all the way through: its winning
        // response has a line recorded on disk that frames and whose lip track
        // decodes, and the quest that owns its topic has a stage to set. None
        // of that is true of every offer — a topic can win on an INFO with no
        // TRDT run at all, plenty of dialogue quests carry no stages, and a
        // handful of vanilla lip tracks hold non-finite curve values
        // (`LipSyncRealDataTests` tallies those). Walking to the next candidate
        // is what keeps the gate about the loop rather than about one file.
        let found = try Self.findAConversationLineOnDisk(world, selection: selection)
        let offer = found.offer

        try Self.expectChoosingRecordsTheLine(world, offer: offer)
        let quest = try Self.expectTheOwningQuestTakesAStage(world, offer: offer)
        try Self.expectTheConversationSurvivesASave(world, offer: offer, quest: quest)

        try Self.writeReport(world: world, selection: selection, voice: found.voice)
    }

    /// Whether the whole gate can be run through one offer.
    private static func isFollowable(_ offer: DialogueTopicOffer, in world: World) -> Bool {
        guard
            world.dialogue.info(offer.info)?.responses.isEmpty == false,
            let owner = world.dialogue.topic(offer.topic)?.owningQuest,
            let quest = world.questStore.quest(owner)
        else {
            return false
        }
        return !quest.stages.isEmpty
    }

    // MARK: - The route

    /// Step 1 — the list. Every offer names the first response in its topic's
    /// file order whose conditions passed, and something was rejected, so the
    /// list is a filter rather than a dump.
    @MainActor
    private static func expectAConditionFilteredList(_ world: World) throws -> DialogueSelection {
        let selection = world.runtime.topics(for: speakerKey)
        #expect(!selection.offers.isEmpty, "the speaker was offered nothing at all")
        #expect(!selection.rejected.isEmpty, "nothing was rejected; the list is not filtered")
        #expect(selection.tally.conditionsEvaluated > 0)

        for offer in selection.offers {
            let winner = try #require(offer.considered.first { $0.isWinner })
            #expect(winner.info == offer.info)
            let infos = world.dialogue.infos(for: offer.topic)
            let winnerIndex = try #require(infos.firstIndex { $0.formID == offer.info })
            #expect(offer.considered.prefix(winnerIndex).allSatisfy { !$0.isWinner })
        }
        return selection
    }

    /// Step 2 — the recording. A winning response's file name is re-derived
    /// from its quest and topic editor IDs, found in the archives under some
    /// voice type, framed, and its embedded lip track decoded. That chain is
    /// what makes a chosen topic audible and the mouth move.
    ///
    /// Candidates are walked in the order the list offers them, and what was
    /// skipped is reported rather than swallowed: a gate that silently took the
    /// twentieth candidate would read as though the first had worked.
    @MainActor
    private static func findAConversationLineOnDisk(
        _ world: World,
        selection: DialogueSelection
    ) throws -> (offer: DialogueTopicOffer, voice: VoiceEvidence) {
        var skipped: [String] = []
        for offer in selection.offers where isFollowable(offer, in: world) {
            guard let info = world.dialogue.info(offer.info) else { continue }
            for derivation in world.locator.fileNames(info: info) {
                let suffix = "\\" + derivation.name
                guard let path = world.voicePaths.first(where: { $0.hasSuffix(suffix) }) else {
                    skipped.append("\(derivation.name): no archive entry")
                    continue
                }
                do {
                    let voice = try evidence(forPath: path, world: world)
                    return (offer, VoiceEvidence(
                        path: voice.path,
                        declaredSeconds: voice.declaredSeconds,
                        lipKeyCount: voice.lipKeyCount,
                        unmappedSlotCount: voice.unmappedSlotCount,
                        skippedCandidates: skipped
                    ))
                } catch {
                    skipped.append("\(derivation.name): \(String(describing: error))")
                }
            }
        }
        Issue.record("no offered line resolved to a playable recording: \(skipped.prefix(5))")
        throw M17AcceptanceError.noPlayableLine
    }

    /// One recording, framed and decoded, or a throw naming which half failed.
    private static func evidence(forPath path: String, world: World) throws -> VoiceEvidence {
        let container = try FUZFile(data: world.vfs.contents(forPath: path))
        let audio = try container.audio()
        #expect(audio.codec.sampleRate > 0)
        guard let lipData = container.lipData else {
            throw M17AcceptanceError.noLipTrack
        }
        let lip = try LIPFile(data: lipData)
        #expect(lip.duration > 0)
        let sample = lip.sample(at: lip.duration / 2)
        let finite = sample.weightsBySlot.values.allSatisfy(\.isFinite)
        #expect(finite)
        let mapped = LipVisemeMapping.map(sample, availableTargets: morphTargets)
        return VoiceEvidence(
            path: path,
            declaredSeconds: audio.declaredDuration ?? 0,
            lipKeyCount: lip.keys.count,
            unmappedSlotCount: mapped.unmappedActiveSlots.count,
            skippedCandidates: []
        )
    }

    /// Step 3 — the choice. Choosing the offered response records it under the
    /// INFO's own key, and the response's result scripts are counted rather than
    /// silently dropped, because this session wires no dispatcher.
    @MainActor
    private static func expectChoosingRecordsTheLine(
        _ world: World,
        offer: DialogueTopicOffer
    ) throws {
        #expect(!world.runtime.hasBeenSaid(offer.info))
        let choice = try world.runtime.choose(offer.info, speaker: speakerKey)
        #expect(world.runtime.hasBeenSaid(offer.info))
        #expect(world.runtime.saidState(of: offer.info).saidCount == 1)
        #expect(choice.dispatchedFragments.isEmpty, "no dispatcher is wired in this session")
    }

    /// Step 4 — the quest. The topic names an owning quest, that quest is
    /// running under the plugin baseline, and the stage a result script would
    /// set lands in the same store the conversation writes said-state into.
    @MainActor
    private static func expectTheOwningQuestTakesAStage(
        _ world: World,
        offer: DialogueTopicOffer
    ) throws -> QuestEvidence {
        let topic = try #require(world.dialogue.topic(offer.topic))
        let owner = try #require(topic.owningQuest, "the offered topic names no quest")
        let state = try world.quests.state(of: owner)
        #expect(state.isRunning, "a topic was offered from a quest that is not running")

        let quest = try #require(world.questStore.quest(owner))
        let stage = try #require(
            quest.stages.map(\.index).sorted().first { !state.isStageDone($0) },
            "the quest has no stage left to set"
        )
        let advanced = try world.quests.setStage(stage, on: owner)
        #expect(advanced.isStageDone(stage))
        return QuestEvidence(quest: owner, editorID: quest.editorID, stage: stage)
    }

    /// Step 5 — the save. Said-state and quest state are both world state, so
    /// one encode and decode carries both, and a runtime rebuilt over the
    /// restored store answers the same way the live one does.
    @MainActor
    private static func expectTheConversationSurvivesASave(
        _ world: World,
        offer: DialogueTopicOffer,
        quest: QuestEvidence
    ) throws {
        let encoded = OpenSkySaveEncoder.encode(
            snapshot: world.store.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
        let file = try OpenSkySaveDecoder.decode(encoded)
        let restored = WorldStateStore()
        restored.restore(from: file.snapshot)

        let quests = QuestRuntime(store: restored, quests: world.questStore)
        #expect(try quests.state(of: quest.quest).isStageDone(quest.stage))

        let runtime = try DialogueRuntime(
            store: restored,
            dialogue: world.dialogue,
            quests: world.questStore,
            questStates: quests.resolution(),
            context: conditionContext()
        )
        #expect(runtime.hasBeenSaid(offer.info), "the said line came back unsaid")
        #expect(runtime.saidState(of: offer.info).saidCount == 1)
    }
}

/// The world builder, the evidence types and the report writer, split off the
/// suite so its own body stays inside the repo's type-length limit — the same
/// split `DialogueMenuRealDataTests` makes.
extension M17AcceptanceRealDataTests {
    // MARK: - Private

    private struct World {
        let store: WorldStateStore
        let dialogue: DialogueStore
        let questStore: QuestStore
        let quests: QuestRuntime
        let runtime: DialogueRuntime
        let locator: VoiceLineLocator
        let vfs: VirtualFileSystem
        let voicePaths: [String]
    }

    private struct VoiceEvidence {
        let path: String
        let declaredSeconds: Double
        let lipKeyCount: Int
        let unmappedSlotCount: Int
        /// Derived names walked past before this one, with why, so the report
        /// states what the install could not play.
        let skippedCandidates: [String]
    }

    private struct QuestEvidence {
        let quest: FormID
        let editorID: String?
        let stage: UInt16
    }

    /// The morph targets a vanilla head carries for speech, which is what
    /// decides whether a lip slot is mapped or unmapped.
    private static let morphTargets = Set(LipVisemeMapping.entries.map(\.target))

    private static var speakerKey: ReferenceKey {
        .plugin(name: "skyrim.esm", objectID: delphineReference)
    }

    private static func conditionContext() throws -> ConditionContext {
        try ConditionContext(
            references: ConditionEvaluatorFixture.references([
                (formID: delphineReference, base: delphineBase)
            ]),
            subject: speakerKey,
            target: .player
        )
    }

    @MainActor
    private static func world() throws -> World {
        let root = try #require(dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let localized = try file.pluginHeader().isLocalized
        let dialogue = DialogueStore(
            file: file, pluginName: "Skyrim.esm", localized: localized
        )
        let questStore = QuestStore(file: file, pluginName: "Skyrim.esm")
        let store = WorldStateStore()
        let quests = QuestRuntime(store: store, quests: questStore)
        let runtime = try DialogueRuntime(
            store: store,
            dialogue: dialogue,
            quests: questStore,
            questStates: quests.resolution(),
            context: conditionContext()
        )
        let vfs = VirtualFileSystem(root: root)
        return World(
            store: store,
            dialogue: dialogue,
            questStore: questStore,
            quests: quests,
            runtime: runtime,
            locator: VoiceLineLocator(dialogue: dialogue, quests: questStore),
            vfs: vfs,
            voicePaths: vfs.archiveEntries().map(\.path).filter { $0.hasSuffix(".fuz") }
        )
    }

    /// The honest-coverage numbers this gate is entitled to state, written to a
    /// gitignored run directory so the log entry's headline has a source.
    @MainActor
    private static func writeReport(
        world: World,
        selection: DialogueSelection,
        voice: VoiceEvidence
    ) throws {
        let tally = selection.tally
        let unknown = tally.rankedUnknownFunctions().prefix(10).map {
            "[INFO] unresolved condition \($0.name): \($0.count)"
        }
        let report = ([
            "[INFO] dialogue index: \(world.dialogue.topicCount) topics, "
                + "\(world.dialogue.infoCount) responses",
            "[INFO] selection: \(selection.offers.count) offered, "
                + "\(selection.rejected.count) rejected, "
                + "\(tally.conditionsEvaluated) conditions evaluated, "
                + "\(tally.failureTotal) unresolved",
            "[INFO] voice corpus: \(world.voicePaths.count) .fuz entries",
            "[INFO] chosen line: \(voice.path)",
            "[INFO] chosen line: "
                + String(format: "%.2f s declared", voice.declaredSeconds)
                + ", \(voice.lipKeyCount) lip keys, "
                + "\(voice.unmappedSlotCount) unmapped viseme slots",
            "[INFO] candidates skipped before it: \(voice.skippedCandidates.count)"
        ] + voice.skippedCandidates.prefix(5).map { "[INFO] skipped \($0)" } + [
        ] + unknown).joined(separator: "\n") + "\n"
        print(report)

        let logs = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs/m17-acceptance", directoryHint: .isDirectory)
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "")
        let run = logs.appending(path: stamp, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        try report.write(
            to: run.appending(path: "report.txt"), atomically: true, encoding: .utf8
        )
        print("[INFO] M17 acceptance report: \(run.path())")
    }
}

/// Thrown to end the run early when the install offers no line this gate can
/// follow, which `Issue.record` has already reported.
private enum M17AcceptanceError: Error {
    case noPlayableLine
    case noLipTrack
}
