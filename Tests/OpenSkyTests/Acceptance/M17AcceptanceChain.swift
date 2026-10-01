// The M17 gate's session: one speaker, a live `GameViewController`, and the
// shipping conversation path, headless. It drives only the app's entry points.
// No cell is resident, so Talk candidates are supplied directly; the pick is
// real. No renderer, so `dialoguemenu.swf` never loads; the engine model is
// tested instead. Everything is invented.

import AppKit
@testable import OpenSky
import OpenSkyDialogue
@testable import OpenSkyDialogueInterface
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyMenus
@testable import OpenSkyQuestsInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
import OpenSkyScriptingFixtures
@testable import OpenSkyWorld
import OpenSkyWorldFixtures
@testable import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import OpenSkyWorldTesting
import simd
import Testing

@MainActor
final class M17AcceptanceChain {
    let controller = GameViewController()
    let session: PapyrusWorldFixture.Session
    let streamer: CellStreamer
    /// Talk activations the world published, in order, so the route asserts the
    /// use key produced an event rather than that a conversation appeared.
    private(set) var activations: [TalkActivationEvent] = []

    private let runner = ManualCellBuildRunner()

    init() throws {
        session = try M17AcceptanceFixture.session(worldState: controller.worldState)
        controller.papyrusBridge = session.bridge
        streamer = CellStreamerFixture.makeStreamer(runner: runner)
        controller.streamer = streamer
        controller.dialogueWorld.wireDialogue(provider: DialogueOnlyProvider(), streamer: streamer)
        // The provider seam carries a store only in a session with game data;
        // this one is synthetic, so the index is installed directly.
        controller.dialogue.index = try M17AcceptanceFixture.dialogueStore()
        // No cell is resident, so the app's own resident-actor walk finds
        // nobody. The speaker is supplied to the same seam it would fill.
        streamer.talk.candidateSource = { [Self.candidate] }
        streamer.talk.activations.add { [weak self] event in
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

    // MARK: - The panel's entry points

    /// Every one of these is a `DialogueControlProviding` member, which is what
    /// the panel's buttons call and what the live keys route into.
    func openDialogue() {
        controller.openDialogue()
    }

    func leaveDialogue() {
        controller.closeDialogue()
    }

    func moveSelection(by delta: Int) {
        for _ in 0 ..< abs(delta) {
            controller.sendDialogueInput(.move(delta < 0 ? .up : .down))
        }
    }

    func choose() {
        controller.sendDialogueInput(.button(.accept))
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
        controller.dialogueSnapshot
    }

    var topicTexts: [String] {
        model.topics.map(\.text)
    }

    /// Said-state as the world state store holds it, which is what a save
    /// carries.
    func saidCount(of info: UInt32) -> UInt32 {
        controller.worldState.component(
            DialogueRuntimeState.self, for: M17AcceptanceFixture.infoKey(info)
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
    /// decoder the Runtime State panel's save control uses.
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
        key: M17AcceptanceFixture.speakerKey,
        reference: FormID(M17AcceptanceFixture.speakerObjectID),
        base: FormID(M17AcceptanceFixture.speakerBase),
        feet: SIMD3(180, 0, 0),
        name: M17AcceptanceFixture.speakerName
    )
}

/// A provider that carries no cells, because none are resident, and no dialogue
/// store, because the chain installs a synthetic one. It exists so the chain
/// can call the app's own `wireDialogue` rather than repeating the two seam
/// assignments that function makes.
nonisolated private struct DialogueOnlyProvider: WorldDataProviding {}
