// Real-data check of the `MQ101` script chain after the cart ride, with no window
// and no world. A fake actor AI records idles, and the test sends the idle's
// animation event itself. The report holds stage numbers and counts only.

import Foundation
import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyQuests
@testable import OpenSkyQuestsInterface
@testable import OpenSkyScripting
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
private final class RecordingActorAI: PapyrusActorAIBridge {
    private(set) var idles: [(idle: ResolvedFormID, actor: ReferenceKey)] = []

    func evaluatePackage(_: ReferenceKey) {}
    func setVehicle(_: ReferenceKey, vehicle _: ReferenceKey?) {}
    func tether(_: ReferenceKey, to _: ReferenceKey) {}
    func setPlayerAIDriven(_: Bool) {}

    func playIdle(_ idle: ResolvedFormID, on actor: ReferenceKey) -> Bool {
        idles.append((idle, actor))
        return true
    }
}

@MainActor
struct OpeningScriptRealDataTests {
    private static let cartDriver = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0654F6)

    /// Stage 42 asks the first cart's driver to climb down. His exit idle sends
    /// `ExitCartEnd`, and the last rider down sets stage 45.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func theFirstCartUnloadsAfterStage42() throws {
        let session = try Session()
        try session.setStage(42)
        #expect(session.actorAI.idles.contains { $0.actor == Self.cartDriver })
        #expect(session.ridersExiting().contains(Self.cartDriver))
        session.finishExits()
        #expect(session.newFaults.isEmpty, "\(session.newFaults)")
        #expect(try session.state().isStageDone(45))
        try session.writeReport(name: "opening-scripts-probe.log")
    }

    /// Stage 43 unloads the second cart's driver and stage 50 the prisoners of the
    /// first cart. A scene sets both in play; here the test sets them.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func eachExitStageCountsItsRiders() throws {
        let session = try Session()
        for stage: UInt16 in [42, 43, 50] {
            try session.setStage(stage)
            session.finishExits()
        }
        #expect(session.newFaults.isEmpty, "\(session.newFaults)")
        let done = try session.state()
        #expect([45, 46, 52].allSatisfy { done.isStageDone($0) }, "\(done.stagesReached)")
        try session.writeReport(name: "opening-exit-stages-probe.log")
    }

    /// Hearthfire's adoption script reads the stopped `HousePurchase` quest's script.
    /// The first cast attaches the quest's scripts.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aStoppedQuestAttachesOnFirstUse() throws {
        let session = try Session()
        let key = try #require(session.questKey(editorID: "HousePurchase"))
        let handle = session.world.objectHandle(for: key)
        #expect(session.world.runtime.siblingInstance?(handle, "HousePurchaseScript") != nil)
    }

    @MainActor
    private final class Session {
        let world: PapyrusWorldRuntime
        let bridge: PapyrusWorldStateBridge
        let actorAI = RecordingActorAI()
        let quest: Quest
        let quests: QuestStore
        let key: ReferenceKey
        private var faultsSeen = 0
        private(set) var newFaults: [String] = []

        init() throws {
            let root = try #require(RealDataEnvironment.dataRoot)
            let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
            quests = QuestStore(file: file, pluginName: "Skyrim.esm")
            quest = try #require(quests.quest(editorID: "MQ101"))
            key = try #require(quests.key(for: quest.formID))
            let worldState = WorldStateStore()
            bridge = PapyrusWorldStateBridge(worldState: worldState)
            world = PapyrusWorldRuntime(runtime: PapyrusRuntime(
                files: [],
                nativeDispatch: PapyrusNativeRegistry.standard(
                    context: PapyrusNativeContext(world: bridge)
                )
            ))
            bridge.world = world
            bridge.actorAI = actorAI
            bridge.questRuntime = QuestRuntime(
                store: worldState, quests: quests,
                locations: LocationStoreLoader.load(root: root, baseFile: file)
            )
            let loader = PexScriptLoader(fileSystem: VirtualFileSystem(root: root))
            world.scriptProvider = { try? loader.load($0) }
            #expect(try bridge.startQuest(for: key))
            drain()
            faultsSeen = world.runtime.tally.faultTotal
        }

        func questKey(editorID: String) -> ReferenceKey? {
            quests.quest(editorID: editorID).flatMap { quests.key(for: $0.formID) }
        }

        func setStage(_ stage: UInt16) throws {
            #expect(try bridge.setQuestStage(stage, for: key))
            drain()
        }

        /// Runs queued events and fragments, and notes each fault they raise.
        func drain() {
            for _ in 0 ..< 64 where !world.eventQueue.isEmpty {
                world.stepFixed()
            }
            let tally = world.runtime.tally
            if tally.faultTotal > faultsSeen {
                newFaults.append(tally.lastFault ?? "fault")
                faultsSeen = tally.faultTotal
            }
        }

        /// The riders that wait for their exit idle to end.
        func ridersExiting() -> [ReferenceKey] {
            world.animationEventListeners
                .filter { $0.value["exitcartend"]?.isEmpty == false }.keys.sorted()
        }

        /// Ends every exit idle that a rider waits for, as its animation would.
        func finishExits() {
            for rider in ridersExiting() {
                world.queueAnimationEvent(sender: rider, name: "ExitCartEnd")
            }
            drain()
        }

        func state() throws -> QuestRuntimeState {
            try #require(bridge.questRuntime).state(of: quest.formID)
        }

        func writeReport(name: String) throws {
            let lines = try [
                "OpenSky opening script probe",
                "stages done: \(state().stagesReached)",
                "aliases filled: \(world.aliasResolution.filledAliasCount)",
                "idles: \(actorAI.idles.count) faults: \(world.runtime.tally.faultTotal)",
                "last fault: \(world.runtime.tally.lastFault ?? "none")"
            ]
            let logs = try RepositoryLogs.directory()
            try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
            try (lines.joined(separator: "\n") + "\n").write(
                to: logs.appending(path: name), atomically: true, encoding: .utf8
            )
        }
    }
}
