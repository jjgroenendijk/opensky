// The detection lines of a combat group: which line each change of its record says,
// who says it, and the waits per group and subtype. Synthetic fighters.

import Foundation
@testable import OpenSkyDialogue
import OpenSkyDialogueFixtures
import OpenSkyDialogueInterface
import OpenSkyFeaturesTesting
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyWorldState
import simd
import Testing

@MainActor
struct DetectionDialogueTests {
    private static let bandit = ReferenceKey.plugin(name: "test.esm", objectID: 0x200)
    private static let archer = ReferenceKey.plugin(name: "test.esm", objectID: 0x201)
    private static let idle: ClosedRange<Double> = 10 ... 25

    private static func member(
        _ key: ReferenceKey, searching: Bool, x: Float = 0, canSpeak: Bool = true
    ) -> DetectionMember {
        DetectionMember(
            key: key, target: .player, feet: SIMD3(x, 0, 0), isSearching: searching,
            canSpeak: canSpeak
        )
    }

    /// Runs one pass and returns the lines asked for, each answered with `found`.
    private static func pass(
        _ members: [DetectionMember], now: Double, state: inout DetectionDialogueState,
        dead: Set<ReferenceKey> = [], found: Bool = true
    ) -> [DetectionLineRequest] {
        var asked: [DetectionLineRequest] = []
        let frame = DetectionDialogueFrame(
            members: members, now: now, targetPositions: [.player: SIMD3(100, 0, 0)],
            deadTargets: dead
        )
        DetectionDialogueCore.pass(frame, idleWait: idle, state: &state) { request in
            asked.append(request)
            return found
        }
        return asked
    }

    @Test func aFightThatStartsOnADetectedTargetSaysNormalToCombat() {
        var state = DetectionDialogueState()
        let lines = Self.pass([Self.member(Self.bandit, searching: false)], now: 0, state: &state)
        #expect(lines.map(\.subtype) == [.normalToCombat])
        #expect(lines.first?.speaker == Self.bandit)
        #expect(state.records[.player] == .combat)
    }

    @Test func aFightThatStartsOnAnUnseenTargetSaysNormalToAlert() {
        var state = DetectionDialogueState()
        let lines = Self.pass([Self.member(Self.bandit, searching: true)], now: 0, state: &state)
        #expect(lines.map(\.subtype) == [.normalToAlert])
        #expect(state.records[.player] == .alert)
    }

    @Test func losingTheTargetSaysCombatToLostByTheMemberNearestItsPlace() {
        var state = DetectionDialogueState()
        _ = Self.pass([Self.member(Self.bandit, searching: false)], now: 0, state: &state)
        let lines = Self.pass([
            Self.member(Self.bandit, searching: true, x: 0),
            Self.member(Self.archer, searching: true, x: 90)
        ], now: 5, state: &state)
        #expect(lines == [
            DetectionLineRequest(subtype: .combatToLost, speaker: Self.archer)
        ])
        #expect(state.records[.player] == .lost)
        #expect(state.wait(for: .lostIdle, about: .player, now: 5) >= 10)
        #expect(state.wait(for: .lostIdle, about: .player, now: 5) <= 25)
    }

    @Test func aSearchingGroupSaysItsIdleLineOnlyAfterTheIdleWait() {
        var state = DetectionDialogueState()
        _ = Self.pass([Self.member(Self.bandit, searching: false)], now: 0, state: &state)
        let searching = [Self.member(Self.bandit, searching: true)]
        _ = Self.pass(searching, now: 1, state: &state)
        #expect(Self.pass(searching, now: 5, state: &state).isEmpty)
        let late = Self.pass(searching, now: 30, state: &state)
        #expect(late.map(\.subtype) == [.lostIdle])
        #expect(Self.pass(searching, now: 32, state: &state).isEmpty)
    }

    @Test func aGroupThatNeverSawTheTargetSaysAlertLines() {
        var state = DetectionDialogueState()
        let searching = [Self.member(Self.bandit, searching: true)]
        _ = Self.pass(searching, now: 0, state: &state)
        #expect(Self.pass(searching, now: 2, state: &state).map(\.subtype) == [.alertIdle])
        let found = Self.pass([Self.member(Self.bandit, searching: false)], now: 3, state: &state)
        #expect(found.map(\.subtype) == [.alertToCombat])
        #expect(Self.pass([], now: 9, state: &state).isEmpty)
        #expect(state.records[.player] == nil)
    }

    @Test func findingALostTargetAgainSaysLostToCombat() {
        var state = DetectionDialogueState()
        _ = Self.pass([Self.member(Self.bandit, searching: false)], now: 0, state: &state)
        _ = Self.pass([Self.member(Self.bandit, searching: true)], now: 1, state: &state)
        let lines = Self.pass([Self.member(Self.bandit, searching: false)], now: 2, state: &state)
        #expect(lines.map(\.subtype) == [.lostToCombat])
    }

    @Test func droppingTheLastTargetSaysTheLineOfTheOldRecord() {
        var state = DetectionDialogueState()
        _ = Self.pass([Self.member(Self.bandit, searching: false)], now: 0, state: &state)
        _ = Self.pass([Self.member(Self.bandit, searching: true)], now: 1, state: &state)
        let lost = Self.pass([], now: 40, state: &state)
        #expect(lost == [
            DetectionLineRequest(subtype: .lostToNormal, speaker: Self.bandit)
        ])
        _ = Self.pass([Self.member(Self.archer, searching: true)], now: 50, state: &state)
        #expect(Self.pass([], now: 60, state: &state).map(\.subtype) == [.alertToNormal])
    }

    @Test func aDeadTargetSaysCombatToNormalAndALiveOneSaysNothing() {
        var state = DetectionDialogueState()
        _ = Self.pass([Self.member(Self.bandit, searching: false)], now: 0, state: &state)
        #expect(Self.pass([], now: 5, state: &state).isEmpty)
        _ = Self.pass([Self.member(Self.bandit, searching: false)], now: 10, state: &state)
        let lines = Self.pass([], now: 15, state: &state, dead: [.player])
        #expect(lines.map(\.subtype) == [.combatToNormal])
    }

    @Test func aLineThatWasNotFoundStartsNoWait() {
        var state = DetectionDialogueState()
        let fighting = [Self.member(Self.bandit, searching: false)]
        _ = Self.pass(fighting, now: 0, state: &state, found: false)
        #expect(state.wait(for: .normalToCombat, about: .player, now: 0) == 0)
    }

    @Test func thePlayerAndAMemberThatCannotSpeakSayNothing() {
        var state = DetectionDialogueState()
        let lines = Self.pass([
            Self.member(.player, searching: false),
            Self.member(Self.bandit, searching: false, canSpeak: false)
        ], now: 0, state: &state)
        #expect(lines.isEmpty)
    }

    @Test func theSubtypeCodesAreTheRecordCodes() {
        #expect(DetectionSubtype.alertIdle.code == "ALIL")
        #expect(DetectionSubtype.lostIdle.code == "LOIL")
        #expect(DetectionSubtype.combatToLost.code == "COLO")
        #expect(DetectionSubtype.allCases.map(\.code).count == 10)
        #expect(DetectionSubtype.lostIdle.isIdle && !DetectionSubtype.lostToCombat.isIdle)
    }

    @Test func theCoordinatorKeepsTheRecordAndFindsNoLineInAnEmptyTopicList() throws {
        let world = try FakeDialogueWorld(
            quests: QuestResolution(defaults: DialogueRuntimeFixture.questStore()),
            context: DialogueRuntimeFixture.context()
        )
        let coordinator = try DialogueCoordinator(
            store: WorldStateStore(), world: world, index: DialogueRuntimeFixture.dialogueStore()
        )
        let frame = DetectionDialogueFrame(
            members: [Self.member(DialogueRuntimeFixture.speakerKey, searching: false)], now: 0
        )
        #expect(coordinator.detectionLines(frame).isEmpty)
        #expect(coordinator.friendDeathLine(speaker: DialogueRuntimeFixture.speakerKey) == nil)
        #expect(coordinator.detectionDialogue.records[.player] == .combat)
        #expect(coordinator.detectionRecords[.player] == .combat)
        let request = DetectionLineRequest(
            subtype: .alertIdle, speaker: DialogueRuntimeFixture.speakerKey
        )
        #expect(DetectionLine(info: FormID(0x90), request: request).request == request)
        #expect(SpeechTimerSettings.vanilla.detectionIdleWait == 10 ... 25)
    }
}
