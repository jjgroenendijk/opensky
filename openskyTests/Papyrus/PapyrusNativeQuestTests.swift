// The `Quest` native family (issue #322), invoked directly against a synthetic
// quest: one test per registered function plus its failure path.
//
// Fixtures are synthetic — never extracted game files (AGENTS.md "Legal & IP
// boundary").

import Foundation
@testable import opensky
import Testing

@MainActor
struct PapyrusNativeQuestTests {
    private struct Fixture {
        let session: PapyrusWorldFixture.Session
        let registry: PapyrusNativeRegistry
        let handle: PapyrusObjectHandle
    }

    private func fixture(startGameEnabled: Bool = true) throws -> Fixture {
        let session = try PapyrusQuestFixture.session(
            quest: PapyrusQuestFixture.quest(startGameEnabled: startGameEnabled)
        )
        PapyrusWorldFixture.drain(session.world)
        return Fixture(
            session: session,
            registry: PapyrusWorldFixture.registry(for: session),
            handle: session.world.objectHandle(for: PapyrusQuestFixture.questKey)
        )
    }

    @discardableResult
    private func call(
        _ functionName: String,
        _ fixture: Fixture,
        receiver: PapyrusObjectHandle?,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeResult {
        fixture.registry.invoke(PapyrusWorldFixture.methodCall(
            "Quest", functionName, receiver: receiver,
            arguments: arguments, returnType: returnType
        ))
    }

    /// A handle no quest is behind: the natives fail with a reason rather than
    /// answering for a quest this session does not define.
    private func strangerHandle(_ fixture: Fixture) -> PapyrusObjectHandle {
        fixture.session.world.objectHandle(
            for: .plugin(name: PapyrusWorldFixture.pluginName, objectID: 0x0000_0DED)
        )
    }

    @Test func isRunningAndIsCompletedReadTheSessionState() throws {
        let fixture = try fixture()
        #expect(call(
            "IsRunning", fixture, receiver: fixture.handle, returnType: .boolean
        ) == .returned(.boolean(true)))
        #expect(call(
            "IsCompleted", fixture, receiver: fixture.handle, returnType: .boolean
        ) == .returned(.boolean(false)))

        #expect(call(
            "CompleteQuest", fixture, receiver: fixture.handle
        ) == .returned(.none))
        #expect(call(
            "IsCompleted", fixture, receiver: fixture.handle, returnType: .boolean
        ) == .returned(.boolean(true)))
        // `CompleteQuest` flags completion and nothing else: the quest is still
        // running afterwards.
        #expect(call(
            "IsRunning", fixture, receiver: fixture.handle, returnType: .boolean
        ) == .returned(.boolean(true)))
    }

    /// `GetCurrentStageID` reports the highest stage reached, and both
    /// spellings of it answer the same. A quest that has reached nothing
    /// reports 0.
    @Test func getStageReportsTheHighestStageReached() throws {
        let fixture = try fixture()
        #expect(call(
            "GetStage", fixture, receiver: fixture.handle, returnType: .integer
        ) == .returned(.integer(0)))

        #expect(call(
            "SetStage", fixture, receiver: fixture.handle,
            arguments: [.integer(20)], returnType: .boolean
        ) == .returned(.boolean(true)))
        #expect(call(
            "SetStage", fixture, receiver: fixture.handle,
            arguments: [.integer(Int32(PapyrusQuestFixture.fragmentStage))],
            returnType: .boolean
        ) == .returned(.boolean(true)))

        for name in ["GetStage", "GetCurrentStageID"] {
            #expect(call(
                name, fixture, receiver: fixture.handle, returnType: .integer
            ) == .returned(.integer(20)))
        }
    }

    /// A stage is done only when it was explicitly visited: reaching 20 does
    /// not make 10 done.
    @Test func getStageDoneOnlyReportsVisitedStages() throws {
        let fixture = try fixture()
        call("SetStage", fixture, receiver: fixture.handle, arguments: [.integer(20)])

        for name in ["GetStageDone", "IsStageDone"] {
            #expect(call(
                name, fixture, receiver: fixture.handle,
                arguments: [.integer(20)], returnType: .boolean
            ) == .returned(.boolean(true)))
            #expect(call(
                name, fixture, receiver: fixture.handle,
                arguments: [.integer(Int32(PapyrusQuestFixture.fragmentStage))],
                returnType: .boolean
            ) == .returned(.boolean(false)))
        }
    }

    /// A stage the quest does not declare leaves the state alone and reports
    /// the documented false, while the tally still records the failure.
    @Test func setStageRefusesAStageTheQuestDoesNotDeclare() throws {
        let fixture = try fixture()
        let result = call(
            "SetStage", fixture, receiver: fixture.handle,
            arguments: [.integer(999)], returnType: .boolean
        )
        #expect(PapyrusWorldFixture.isInvalidArguments(result))
        #expect(try PapyrusQuestFixture.state(fixture.session).stagesReached.isEmpty)
    }

    /// A negative stage names nothing a QUST can declare and is refused before
    /// it reaches the quest layer.
    @Test func setStageRefusesANegativeStage() throws {
        let fixture = try fixture()
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "SetStage", fixture, receiver: fixture.handle,
            arguments: [.integer(-1)], returnType: .boolean
        )))
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "SetStage", fixture, receiver: fixture.handle, returnType: .boolean
        )))
    }

    /// `Start` and `Stop` move the running flag and the script instances with
    /// it. Stopping keeps the stages the quest reached.
    @Test func startAndStopMoveTheRunningFlag() throws {
        let fixture = try fixture(startGameEnabled: false)
        #expect(call(
            "IsRunning", fixture, receiver: fixture.handle, returnType: .boolean
        ) == .returned(.boolean(false)))

        #expect(call(
            "Start", fixture, receiver: fixture.handle, returnType: .boolean
        ) == .returned(.boolean(true)))
        #expect(fixture.session.world.questInstanceKeys.count == 2)
        call(
            "SetStage", fixture, receiver: fixture.handle,
            arguments: [.integer(20)], returnType: .boolean
        )

        #expect(call("Stop", fixture, receiver: fixture.handle) == .returned(.none))
        #expect(call(
            "IsRunning", fixture, receiver: fixture.handle, returnType: .boolean
        ) == .returned(.boolean(false)))
        #expect(fixture.session.world.questInstanceKeys.isEmpty)
        #expect(try PapyrusQuestFixture.state(fixture.session).stagesReached == [20])
    }

    /// A start-up stage is the one stage a stopped quest accepts, and setting
    /// it starts the quest.
    @Test func aStartUpStageStartsAStoppedQuest() throws {
        let fixture = try fixture(startGameEnabled: false)
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "SetStage", fixture, receiver: fixture.handle,
            arguments: [.integer(20)], returnType: .boolean
        )))
        #expect(call(
            "SetStage", fixture, receiver: fixture.handle,
            arguments: [.integer(Int32(PapyrusQuestFixture.startUpStage))],
            returnType: .boolean
        ) == .returned(.boolean(true)))
        #expect(try PapyrusQuestFixture.state(fixture.session).isRunning)
        #expect(fixture.session.world.questInstanceKeys.count == 2)
    }

    /// The three objective setters are independent, each defaulting to true,
    /// and each refusing an objective the quest does not declare.
    @Test func objectiveSettersAreIndependent() throws {
        let fixture = try fixture()
        let index = Int32(PapyrusQuestFixture.objectiveIndex)
        call(
            "SetObjectiveDisplayed",
            fixture,
            receiver: fixture.handle,
            arguments: [.integer(index)]
        )
        call(
            "SetObjectiveCompleted",
            fixture,
            receiver: fixture.handle,
            arguments: [.integer(index), .boolean(true)]
        )

        let objective = try PapyrusQuestFixture.state(fixture.session)
            .objective(PapyrusQuestFixture.objectiveIndex)
        #expect(objective.isDisplayed)
        #expect(objective.isCompleted)
        #expect(!objective.isFailed)

        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "SetObjectiveFailed", fixture, receiver: fixture.handle,
            arguments: [.integer(77)]
        )))
    }

    /// Every quest native refuses a handle no quest in this session is behind,
    /// rather than answering for a quest that does not exist.
    @Test func everyNativeRefusesAnUnknownQuestHandle() throws {
        let fixture = try fixture()
        let stranger = strangerHandle(fixture)
        let calls: [(String, [PapyrusValue])] = [
            ("IsRunning", []), ("IsCompleted", []), ("GetStage", []),
            ("GetCurrentStageID", []), ("GetStageDone", [.integer(10)]),
            ("IsStageDone", [.integer(10)]), ("Start", []), ("Stop", []),
            ("CompleteQuest", []), ("SetStage", [.integer(10)]),
            ("SetCurrentStageID", [.integer(10)]),
            ("SetObjectiveDisplayed", [.integer(10)]),
            ("SetObjectiveCompleted", [.integer(10)]),
            ("SetObjectiveFailed", [.integer(10)])
        ]
        for (name, arguments) in calls {
            #expect(
                PapyrusWorldFixture.isInvalidArguments(call(
                    name, fixture, receiver: stranger, arguments: arguments
                )),
                "\(name) answered for an unknown quest"
            )
            #expect(
                PapyrusWorldFixture.isInvalidArguments(call(
                    name, fixture, receiver: nil, arguments: arguments
                )),
                "\(name) answered with no receiver"
            )
        }
    }

    /// A session with no quest index at all — a synthetic scene — fails every
    /// quest native with the seam's own error rather than inventing state.
    @Test func aSessionWithoutQuestDataFailsHonestly() throws {
        let fixture = try fixture()
        fixture.session.bridge.questRuntime = nil
        #expect(PapyrusWorldFixture.isInvalidArguments(call(
            "IsRunning", fixture, receiver: fixture.handle, returnType: .boolean
        )))
    }
}
