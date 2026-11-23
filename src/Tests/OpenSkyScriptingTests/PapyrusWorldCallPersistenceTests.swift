// A script call that waits at a save goes on after the load: a timer wait keeps its
// remaining time, and a wait on a queued quest start gets the start's answer.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
@testable import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
import Testing

@MainActor
struct PapyrusWorldCallPersistenceTests {
    private static let scriptName = "WaiterScript"
    private static let key = PapyrusWorldFixture.key(objectID: 1, script: scriptName)
    private static let quest = ReferenceKey.plugin(
        name: PapyrusWorldFixture.pluginName, objectID: 0x900
    )

    @Test("a call that waits on a timer goes on after the load with the time it had left")
    func timerWaitContinuesAfterALoad() throws {
        let body = PapyrusWorldFixture.probeBody(note: "woke", waitSeconds: 3)
        let saved = try Self.world(onLoad: body)
        saved.world.scriptEvents.stepFixed()
        saved.world.scriptEvents.stepFixed()
        let snapshot = saved.world.callStates()

        let call = try #require(snapshot.calls.first)
        #expect(snapshot.calls.count == 1)
        #expect(call.owner == Self.key)
        #expect(call.frames.map(\.script.localizedLowercase) == [Self.scriptName.lowercased()])
        guard case let .realSeconds(remaining, answer) = call.wake else {
            Issue.record("the wake is \(call.wake)")
            return
        }
        #expect(remaining > 0 && remaining < 3)
        #expect(answer == nil)

        let loaded = try Self.world(onLoad: body, queued: false)
        loaded.world.lifecycle.restore(calls: snapshot)
        #expect(loaded.world.callStates() == snapshot, "a restored call saves the same again")

        let stepsWithoutLoad = Self.stepsUntilNote(saved)
        let stepsAfterLoad = Self.stepsUntilNote(loaded)
        #expect(stepsWithoutLoad > 0)
        #expect(stepsAfterLoad == stepsWithoutLoad)
        #expect(loaded.probe.notes == ["woke"])
        #expect(loaded.world.callStates().isEmpty)
    }

    @Test("a call that waits on a queued quest start gets the start's answer after the load")
    func questStartWaitIsAnsweredAfterALoad() throws {
        let saved = try Self.world(onLoad: Self.askerBody)
        var reports: [PapyrusValue] = []
        Self.answerStarts(of: saved) { reports.append($0) }
        saved.world.scriptEvents.stepFixed()
        let snapshot = saved.world.callStates()

        let call = try #require(snapshot.calls.first)
        #expect(call.wake == .questStart(quest: Self.quest, thenFragments: false))
        #expect(call.resume == .assign("started"))
        #expect(reports.isEmpty)

        let loaded = try Self.world(onLoad: Self.askerBody, queued: false)
        var loadedReports: [PapyrusValue] = []
        Self.answerStarts(of: loaded) { loadedReports.append($0) }
        loaded.world.lifecycle.restore(calls: snapshot)
        loaded.world.scriptEvents.stepFixed()
        #expect(loadedReports.isEmpty, "the start has not ended yet")

        loaded.world.questRuns.answerStartWaits(of: Self.quest, started: true)
        PapyrusWorldFixture.drain(loaded.world)
        #expect(loadedReports == [.boolean(true)])
        #expect(loaded.world.skips.counts[.unrestorableSaveCall] == nil)
    }

    @Test("a load drops the calls of the session it replaces")
    func aLoadCancelsTheOldCalls() throws {
        let body = PapyrusWorldFixture.probeBody(note: "woke", waitSeconds: 3)
        let world = try Self.world(onLoad: body)
        world.world.scriptEvents.stepFixed()
        #expect(world.world.callStates().calls.count == 1)

        world.world.lifecycle.restore(calls: .empty)
        PapyrusWorldFixture.drain(world.world)
        #expect(world.probe.notes.isEmpty)
        #expect(world.world.callStates().isEmpty)
    }

    @Test("a saved call that cannot continue is counted and dropped")
    func unknownScriptOrChangedFunctionIsCounted() throws {
        let body = PapyrusWorldFixture.probeBody(note: "woke", waitSeconds: 3)
        let saved = try Self.world(onLoad: body)
        saved.world.scriptEvents.stepFixed()
        let good = try #require(saved.world.callStates().calls.first)

        var unknownScript = good
        unknownScript.frames[0].script = "NoSuchScript"
        var changedFunction = good
        changedFunction.frames[0].instructionCount += 1
        var unknownOwner = good
        unknownOwner.owner = PapyrusWorldFixture.key(objectID: 77, script: Self.scriptName)
        var snapshot = PapyrusCallSnapshot()
        snapshot.calls = [unknownScript, changedFunction, unknownOwner]

        let loaded = try Self.world(onLoad: body, queued: false)
        loaded.world.lifecycle.restore(calls: snapshot)
        #expect(loaded.world.skips.counts[.unrestorableSaveCall] == 3)
        #expect(loaded.world.callStates().isEmpty)
    }

    @Test("a wait the save does not keep goes on at the next step with the default answer")
    func aLostWaitResumesWithTheDefault() throws {
        let saved = try Self.world(onLoad: Self.askerBody)
        Self.answerStarts(of: saved) { _ in }
        saved.world.scriptEvents.stepFixed()
        var snapshot = saved.world.callStates()
        snapshot.calls[0].wake = .lost
        snapshot.calls[0].returnType = "Bool"

        let loaded = try Self.world(onLoad: Self.askerBody, queued: false)
        var reports: [PapyrusValue] = []
        Self.answerStarts(of: loaded) { reports.append($0) }
        loaded.world.lifecycle.restore(calls: snapshot)
        PapyrusWorldFixture.drain(loaded.world)
        #expect(reports == [.boolean(false)])
    }

    @Test("objects and a shared array in a waiting call come back after the load")
    func objectsAndSharedArraysRoundTrip() throws {
        let saved = try Self.world(onLoad: Self.holderBody)
        saved.world.scriptEvents.stepFixed()
        let snapshot = saved.world.callStates()

        let call = try #require(snapshot.calls.first)
        #expect(snapshot.arrays.count == 1, "two variables share one array")
        #expect(snapshot.arrays.first?.elements == [.integer(4), .integer(0)])
        #expect(call.frames.first?.slots.contains(.instance(Self.key)) == true)
        #expect(call.frames.first?.slots.filter { $0 == .array(0) }.count == 2)

        let loaded = try Self.world(onLoad: Self.holderBody, queued: false)
        loaded.world.lifecycle.restore(calls: snapshot)
        #expect(loaded.world.callStates() == snapshot)
    }

    // MARK: Fixtures

    private struct World {
        let world: PapyrusWorldRuntime
        let probe: PapyrusWorldProbeDispatch
    }

    /// `started = Probe.Start()`, then `Probe.Report(started)`.
    private static var askerBody: PexFunction {
        PexFixture.runtimeFunction(
            locals: [PexTypedName(name: "started", typeName: "Bool")],
            instructions: [
                PapyrusTestSupport.instruction(
                    .callStatic, .identifier("Probe"), .identifier("Start"),
                    .identifier("started"), .integer(0)
                ),
                PapyrusTestSupport.instruction(
                    .callStatic, .identifier("Probe"), .identifier("Report"),
                    .identifier("::nonevar"), .integer(1), .identifier("started")
                )
            ]
        )
    }

    /// `me = self`, `first = new Int[2]`, `first[0] = 4`, `second = first`, then
    /// `Utility.Wait(3)`.
    private static var holderBody: PexFunction {
        PexFixture.runtimeFunction(
            locals: [
                PexTypedName(name: "me", typeName: scriptName),
                PexTypedName(name: "first", typeName: "Int[]"),
                PexTypedName(name: "second", typeName: "Int[]")
            ],
            instructions: [
                PapyrusTestSupport.instruction(.assign, .identifier("me"), .identifier("self")),
                PapyrusTestSupport.instruction(.arrayCreate, .identifier("first"), .integer(2)),
                PapyrusTestSupport.instruction(
                    .arraySetElement, .identifier("first"), .integer(0), .integer(4)
                ),
                PapyrusTestSupport.instruction(
                    .assign, .identifier("second"), .identifier("first")
                ),
                PapyrusTestSupport.instruction(
                    .callStatic, .identifier("Utility"), .identifier("Wait"),
                    .identifier("::nonevar"), .integer(1), .float(3)
                )
            ]
        )
    }

    /// `Probe.Start` waits for the queued start of the quest; `Probe.Report` hands its
    /// argument to `report`.
    private static func answerStarts(
        of fixture: World, report: @escaping (PapyrusValue) -> Void
    ) {
        let world = fixture.world
        fixture.probe.probeHandler = { [weak world] call, _ in
            if PapyrusRuntime.matches(call.functionName, "Start") {
                return world?.questRuns.awaitQuestStart(of: quest, thenFragments: false)
            }
            if PapyrusRuntime.matches(call.functionName, "Report") {
                report(call.arguments.first ?? .none)
                return .returned(.none)
            }
            return nil
        }
    }

    private static func stepsUntilNote(_ fixture: World) -> Int {
        for step in 1 ... 16 {
            fixture.world.scriptEvents.stepFixed()
            if !fixture.probe.notes.isEmpty {
                return step
            }
        }
        return 0
    }

    /// A world with the waiter attached, whose `OnLoad` is `body`. The event is queued
    /// unless `queued` is false: the world a save loads into has the same script and no event.
    private static func world(onLoad body: PexFunction, queued: Bool = true) throws -> World {
        let probe = PapyrusWorldProbeDispatch()
        let script = PapyrusWorldFixture.eventScript(scriptName, events: [("OnLoad", body)])
        let world = PapyrusWorldFixture.worldRuntime(
            objects: [script], nativeDispatch: probe, fixedStepSeconds: 1
        )
        world.runtime.nativeTiming = .runToEnd
        try world.attach(
            cell: PapyrusWorldFixture.cell,
            references: PapyrusWorldFixture.index([PapyrusWorldFixture.referenceEntry(
                objectID: 1, scripts: [.init(scriptName, properties: [])]
            )]),
            formIDResolver: PapyrusWorldFixture.resolver,
            firstIntegration: true
        )
        world.eventQueue = queued
            ? [PapyrusScriptEvent(target: key, functionName: "OnLoad", arguments: [])]
            : []
        return World(world: world, probe: probe)
    }
}
