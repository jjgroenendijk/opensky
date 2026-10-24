// The M17 gate's session: one speaker, a live `GameSessionScope`, and the
// shipping conversation path, headless. It drives only the app's entry points.
// No cell is resident, so Talk candidates are supplied directly; the pick is
// real. No renderer, so `dialoguemenu.swf` never loads; the engine model is
// tested instead. Everything is invented.

import AppKit
@testable import OpenSky
@testable import OpenSkyCells
import OpenSkyDialogue
@testable import OpenSkyDialogueInterface
@testable import OpenSkyFormatsESM
import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyPlayer
@testable import OpenSkyQuestsInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

@MainActor
final class DialogueAcceptanceChain {
    let controller: GameSessionScope
    let session: PapyrusWorldFixture.Session
    let streamer: CellStreamer
    /// Talk activations the world published, in order, so the route asserts the
    /// use key produced an event rather than that a conversation appeared.
    private(set) var activations: [TalkActivationEvent] = []

    private let runner = ManualCellBuildRunner()

    init() throws {
        // The scope is built over the stores, so `controller.dialogue` reads them.
        let data = try WorldDataStores(
            scriptFormIDResolver: FormIDResolver(pluginName: "Skyrim.esm", masters: []),
            dialogueStore: DialogueAcceptanceFixture.dialogueStore()
        )
        controller = GameSessionScope(
            worldData: data, cellRunner: nil, gameSession: nil, services: GameAppServices()
        )
        session = try DialogueAcceptanceFixture.session(worldState: controller.worldState)
        controller.scripts = ScriptCoordinator(
            world: controller.scriptWorld, runtime: session.world, bridge: session.bridge
        )
        streamer = CellStreamerFixture.makeStreamer(runner: runner)
        controller.streamer = streamer
        controller.dialogueWorld.wireDialogue(provider: data, streamer: streamer)
        // No cell is resident, so the app's own resident-actor walk finds
        // nobody. The speaker is supplied to the same seam it would fill.
        streamer.talk.candidateSource = { [Self.candidate] }
        streamer.talk.activations.register(.log) { [weak self] event in
            self?.activations.append(event)
        }
        PapyrusWorldFixture.drain(session.world)
    }

    // MARK: - The world's own entry point

    /// The use key on an actor under the crosshair: the view ray picks the nearest
    /// Talk candidate and the activation fans out to subscribers. Returns the
    /// picked speaker so a step can assert it.
    @discardableResult
    func pressUseKeyOnTheSpeaker() throws -> ReferenceKey {
        let ray = try #require(InteractionRay(
            origin: Self.eye,
            direction: SIMD3(1, 0, 0),
            maximumDistance: InteractionRay.defaultMaximumDistance
        ))
        let hit = try #require(TalkTargetPicker.nearest(
            ray: ray, candidates: streamer.talk.candidateSource?() ?? []
        ))
        streamer.talk.speaker = hit.candidate.key
        streamer.talk.activations(TalkActivationEvent(speaker: hit.candidate.key))
        return hit.candidate.key
    }

    // MARK: - The menu's entry points

    /// The live keys route into the same menu calls.
    func openDialogue() {
        controller.dialogueMenu.openFromCrosshair()
    }

    func leaveDialogue() {
        controller.dialogueMenu.close()
    }

    func moveSelection(by delta: Int) {
        for _ in 0 ..< abs(delta) {
            controller.dialogueMenu.route(.move(delta < 0 ? .up : .down))
        }
    }

    func choose() {
        controller.dialogueMenu.route(.button(.accept))
    }

    /// Chooses the row whose text reads `text`, which is how a player picks a
    /// topic: by what it says, not by its index.
    func chooseTopic(named text: String) throws {
        let index = try #require(
            model.topics.firstIndex { $0.text == text },
            "no topic reads \"\(text)\" — the list is \(model.topics.map(\.text))"
        )
        moveSelection(by: index - model.selectedIndex)
        choose()
    }

    /// Says the current line to its end, as Enter does, and returns the list.
    /// Stops when the list is back or a goodbye closes the conversation. The bound
    /// is a runaway guard.
    func finishTheLine() {
        var guardCount = 0
        while controller.dialogueMenu.isOpen, model.state != .topicList, guardCount < 16 {
            choose()
            guardCount += 1
        }
    }

    // MARK: - Reading the session

    var model: DialogueMenuModel {
        controller.dialogueMenu.model
    }

    var snapshot: DialogueControlSnapshot {
        controller.dialogueMenu.snapshot
    }

    var topicTexts: [String] {
        model.topics.map(\.text)
    }

    /// Said-state as the world state store holds it, which is what a save
    /// carries.
    func saidCount(of info: UInt32) -> UInt32 {
        controller.worldState.component(
            DialogueRuntimeState.self, for: DialogueAcceptanceFixture.infoKey(info)
        )?.saidCount ?? 0
    }

    /// The probe quest's stage state, read through `QuestRuntime` rather than
    /// through the bridge that wrote it.
    func questState() throws -> QuestRuntimeState {
        try PapyrusQuestFixture.state(session)
    }

    /// Runs whatever the last choice queued on the Papyrus VM, which the app
    /// does on its own frame.
    func drainScripts() {
        PapyrusWorldFixture.drain(session.world)
    }

    /// The world state a save would write, taken through the same encoder and
    /// decoder the Runtime State readout's save control uses.
    func roundTripThroughASave() throws -> WorldStateStore {
        let encoded = OpenSkySaveEncoder.encode(
            snapshot: controller.worldState.snapshot(),
            fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: OpenSkySaveFixture.metadata
        )
        let file = try OpenSkySaveDecoder.decode(encoded)
        let restored = WorldStateStore()
        restored.restore(from: file.snapshot)
        return restored
    }

    // MARK: - Fixtures

    /// Eye height at the origin, looking down +X at the speaker.
    static let eye = SIMD3<Float>(0, 0, 120)

    static let candidate = TalkCandidate(
        key: DialogueAcceptanceFixture.speakerKey,
        reference: FormID(DialogueAcceptanceFixture.speakerObjectID),
        base: FormID(DialogueAcceptanceFixture.speakerBase),
        feet: SIMD3(180, 0, 0),
        name: DialogueAcceptanceFixture.speakerName
    )
}
