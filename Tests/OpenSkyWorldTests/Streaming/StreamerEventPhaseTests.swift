// Each streamer event runs its handlers in phase order, whatever order the
// wiring registered them in. The pinned orders are the ones the game relies on.

import OpenSkyGameData
import OpenSkyWorld
import OpenSkyWorldFixtures
import OpenSkyWorldInterface
import OpenSkyWorldTesting
import Testing

@MainActor
struct StreamerEventPhaseTests {
    @Test func interactionStepsRunAudioScriptsItemsThenAgentEvents() {
        #expect(InteractionStep.allCases == [.audio, .scripts, .worldItems, .agentEvents])
        let schedule = FrameSchedule<InteractionStep, Int>()
        var order: [InteractionStep] = []
        for step in InteractionStep.allCases.reversed() {
            schedule.register(step) { _ in order.append(step) }
        }
        schedule(0)
        #expect(order == InteractionStep.allCases)
    }

    /// The leveled rolls freeze after the reset and before the scripts read inventories.
    @Test func cellResetPreparesBeforeTheScriptsAttachAndQueuesAfter() {
        #expect(CellAttachStep.allCases == [
            .resetPrepare, .leveledRolls, .scripts, .resetEnqueue, .agentEvents
        ])
        #expect(CellDetachStep.allCases == [.scripts, .reset, .agentEvents])
    }

    @Test func theRefusalStepsAndTheTriggerStepsKeepTheirOrder() {
        #expect(ActivationRefusalStep.allCases == [.lockpicking, .mount, .agentEvents])
        #expect(TriggerTransitionStep.allCases == [.readout, .scripts])
    }

    @Test func theMountCheckAnswersBeforeTheLockCheck() {
        var gate = ActivationGateSeam()
        gate.register(.lock) { _ in .locked(level: 25, key: nil) }
        gate.register(.mount) { _ in .mounted }
        #expect(gate.refusal(for: Self.target) == .mounted)
    }

    @Test func aNilAnswerPassesThePressToTheNextCheck() {
        var gate = ActivationGateSeam()
        gate.register(.lock) { _ in .locked(level: 25, key: nil) }
        gate.register(.mount) { _ in nil }
        #expect(gate.refusal(for: Self.target) == .locked(level: 25, key: nil))
    }

    @Test func withoutChecksEveryPressPasses() {
        #expect(ActivationGateSeam().refusal(for: Self.target) == nil)
    }

    @Test func aCellAttachCarriesTheIntegrationFlagToEveryStep() {
        let streamer = CellStreamerFixture.makeStreamer(runner: ManualCellBuildRunner())
        var seen: [CellAttachStep] = []
        streamer.onCellAttached.register(.agentEvents) { _ in seen.append(.agentEvents) }
        streamer.onCellAttached.register(.scripts) { attachment in
            #expect(!attachment.isFirstIntegration)
            seen.append(.scripts)
        }
        streamer.onCellAttached(CellAttachment(
            scene: CellStreamerFixture.cellScene(),
            isFirstIntegration: false
        ))
        #expect(seen == [.scripts, .agentEvents])
    }

    private static let target = WorldAudioDirectorFixture.makeInteractionEvent(sounds: nil).target
}
