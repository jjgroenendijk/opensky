// The M17 gate's session (issue #209): one speaker, one live `GameViewController`
// and the shipping conversation path, headless.
//
// The gate statement is a loop through the app rather than through the dialogue
// runtime, so the harness drives the app's own entry points and asserts engine
// models at the far end, exactly as the M13-M16 gates did. The use key's
// activation reaches `GameViewController.beginDialogue` through the streamer's
// Talk seam the app itself wires in `wireDialogue`; the panel's Open, Up, Down,
// Choose and Leave reach it through `DialogueControlProviding`, which is the
// same `MenuInputEvent` path the live keys take. Nothing here calls a dialogue
// method the shipping surfaces do not.
//
// Two deliberate simplifications against a running app, both stated so a
// failure is never mistaken for one of them:
//
// * No cell is resident, so the streamer has no actors to walk and the Talk
//   candidate list is supplied directly. The pick itself is real —
//   `TalkTargetPicker.nearest` over the same view ray the crosshair casts — and
//   the occlusion rule that a solid hit in front of an actor wins belongs to
//   `CellStreamerInteraction`, which its own suites cover.
// * There is no renderer, so `dialoguemenu.swf` never loads. The movie contract
//   is `DialogueMenuMovieBridgeTests` and the vanilla movie is driven by
//   `openskycli swf dialogue-menu`; what is under test here is the engine model
//   the movie is published from, which is authoritative for the selection
//   either way (`GameViewControllerDialogueMenu.routeDialogueInput`).
//
// Everything is invented — no packfile bytes, no extracted records, no voice
// files (AGENTS.md "Legal & IP boundary").

import AppKit
@testable import opensky
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
        streamer = CellStreamerTests.makeStreamer(runner: runner)
        controller.streamer = streamer
        controller.wireDialogue(provider: DialogueOnlyProvider(), streamer: streamer)
        // The provider seam carries a store only in a session with game data;
        // this one is synthetic, so the index is installed directly.
        controller.dialogue.store = try M17AcceptanceFixture.dialogueStore()
        // No cell is resident, so the app's own resident-actor walk finds
        // nobody. The speaker is supplied to the same seam it would fill.
        streamer.talk.candidateSource = { [Self.candidate] }
        streamer.talk.activations.add { [weak self] event in
            self?.activations.append(event)
        }
        PapyrusWorldFixture.drain(session.world)
    }

    // MARK: - The world's own entry point

    /// What the use key does on an actor under the crosshair: the view ray
    /// picks the nearest Talk candidate, the streamer retains it, and the
    /// activation fans out to whoever subscribed — which in the app is the
    /// dialogue menu.
    ///
    /// Returns the picked speaker so a route step can assert the pick rather
    /// than assume it.
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
        streamer.talk.activations(TalkActivationEvent(
            speaker: hit.candidate.key,
            target: InteractionTarget(
                interaction: PlacedInteraction(
                    reference: hit.candidate.reference,
                    base: hit.candidate.base,
                    position: hit.candidate.feet,
                    name: hit.candidate.name,
                    action: .talk,
                    actionLabel: InteractionAction.talk.defaultLabel,
                    sounds: nil
                ),
                hitPosition: hit.candidate.feet,
                distance: hit.distance
            )
        ))
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

    /// Says the line that is being delivered to its end, which is what pressing
    /// Enter through a response does, and hands the list back.
    ///
    /// A greeting is delivered the same way a chosen response is, so both
    /// states are driven here; the loop stops when the list is back or when a
    /// goodbye has closed the conversation. The bound is a runaway guard, not a
    /// run count: no fixture response has sixteen runs.
    func finishTheLine() {
        var guardCount = 0
        while controller.dialogue.isOpen, model.state != .topicList, guardCount < 16 {
            choose()
            guardCount += 1
        }
    }

    // MARK: - Reading the session

    var model: DialogueMenuModel {
        controller.dialogue.model
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
nonisolated private final class DialogueOnlyProvider: CellSceneProvider {
    func buildCell(at coordinate: CellCoordinate, state _: WorldStateSnapshot) throws -> CellScene {
        throw CellSceneError.cellNotFound(
            worldspaceEditorID: "M17", gridX: coordinate.x, gridY: coordinate.y
        )
    }

    func evict(droppingMeshKeys _: Set<String>, droppingTextureKeys _: Set<String>) {}
}
