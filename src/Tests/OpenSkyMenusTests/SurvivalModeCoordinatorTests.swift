// The Survival Mode answer: what is written to the plugin's globals, and when the
// setting follows the session instead.

@testable import OpenSkyGameData
@testable import OpenSkyMenus
import Testing

private final class FakeSurvivalWorld: SurvivalModeWorld {
    var values: [String: Float] = [
        SurvivalModeCore.promptedEditorID: 0, SurvivalModeCore.toggleEditorID: 0,
        SurvivalModeCore.enabledEditorID: 0, SurvivalModeCore.canBeEnabledEditorID: 0
    ]
    var writes: [String] = []

    func survivalGlobal(_ editorID: String) -> Float? {
        values[editorID]
    }

    func setSurvivalGlobal(_ value: Float, editorID: String) {
        values[editorID] = value
        writes.append("\(editorID)=\(Int(value))")
    }
}

struct SurvivalModeCoordinatorTests {
    private let unanswered = SurvivalModeGlobals(
        prompted: false, toggle: false, enabled: false, canBeEnabled: true
    )

    @Test func anOpenQuestionIsAnsweredUnlessThePlayerWantsToBeAsked() {
        #expect(SurvivalModeCore.step(globals: unanswered, answer: .on, setting: true)
            == .answer(true))
        #expect(SurvivalModeCore.step(globals: unanswered, answer: .off, setting: false)
            == .answer(false))
        #expect(SurvivalModeCore.step(globals: unanswered, answer: .ask, setting: false) == .none)
    }

    @Test func anAnsweredQuestionMovesTheSettingToTheSessionsChoice() {
        var answered = unanswered
        answered.prompted = true
        answered.toggle = true
        #expect(SurvivalModeCore.step(globals: answered, answer: .off, setting: false)
            == .mirror(true))
        #expect(SurvivalModeCore.step(globals: answered, answer: .ask, setting: true) == .none)
    }

    @Test func theAskSettingAndTheEnvironmentPickTheAnswer() {
        #expect(SurvivalModeCore.answer(ask: true, setting: true) == .ask)
        #expect(SurvivalModeCore.answer(ask: false, setting: true) == .on)
        #expect(SurvivalModeAnswer.forced(environment: ["OPENSKY_SURVIVAL_MODE": "OFF"]) == .off)
        #expect(SurvivalModeAnswer.forced(environment: ["OPENSKY_SURVIVAL_MODE": "maybe"]) == nil)
        #expect(SurvivalModeAnswer.forced(environment: [:]) == nil)
    }

    @Test @MainActor
    func aTickWritesWhatPressingNoWrites() {
        let world = FakeSurvivalWorld()
        let store = PlayerSettingsStore(persistence: nil)
        let coordinator = SurvivalModeCoordinator(store: store, world: world, forcedAnswer: nil)
        coordinator.tick()
        #expect(world.writes == ["Survival_ModeToggle=0", "Survival_PlayerHasBeenPrompted=1"])
        coordinator.tick()
        #expect(world.writes.count == 2)
    }

    @Test @MainActor
    func theAskSettingLeavesTheQuestionToThePlugin() {
        let world = FakeSurvivalWorld()
        let store = PlayerSettingsStore(persistence: nil)
        store.set(.survivalModeAsk, to: 1)
        let coordinator = SurvivalModeCoordinator(store: store, world: world, forcedAnswer: nil)
        coordinator.tick()
        #expect(world.writes.isEmpty)
        world.values[SurvivalModeCore.promptedEditorID] = 1
        world.values[SurvivalModeCore.toggleEditorID] = 1
        coordinator.tick()
        #expect(store.bool(.survivalMode))
        #expect(world.writes.isEmpty)
    }

    @Test @MainActor
    func aForcedAnswerWinsOverTheSettings() {
        let world = FakeSurvivalWorld()
        let store = PlayerSettingsStore(persistence: nil)
        store.set(.survivalModeAsk, to: 1)
        let coordinator = SurvivalModeCoordinator(store: store, world: world, forcedAnswer: .on)
        coordinator.tick()
        #expect(world.values[SurvivalModeCore.toggleEditorID] == 1)
        #expect(world.values[SurvivalModeCore.promptedEditorID] == 1)
        #expect(coordinator.survivalModeSnapshot.lines.first == "Answer: on (launch option)")
        #expect(!store.bool(.survivalMode))
    }

    @Test @MainActor
    func changingTheSettingTurnsTheModeOnOrOff() {
        let world = FakeSurvivalWorld()
        let store = PlayerSettingsStore(persistence: nil)
        let coordinator = SurvivalModeCoordinator(store: store, world: world, forcedAnswer: nil)
        coordinator.setSurvivalMode(true)
        #expect(world.values[SurvivalModeCore.toggleEditorID] == 1)
        #expect(world.values[SurvivalModeCore.promptedEditorID] == 1)
        coordinator.setSurvivalMode(false)
        #expect(world.values[SurvivalModeCore.toggleEditorID] == 0)
    }

    @Test @MainActor
    func withoutThePluginNothingIsWritten() {
        let world = FakeSurvivalWorld()
        world.values = [:]
        let store = PlayerSettingsStore(persistence: nil)
        let coordinator = SurvivalModeCoordinator(store: store, world: world, forcedAnswer: .on)
        coordinator.tick()
        coordinator.setSurvivalMode(true)
        #expect(world.writes.isEmpty)
        #expect(coordinator.survivalModeSnapshot.lines == [
            "Answer: on (launch option)",
            "Plugin: not loaded"
        ])
    }
}
