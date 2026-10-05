// The presentation natives reach the session's presenter: notifications, the
// `Message` script, and the camera calls. A `Message.Show` box suspends its
// script until the engine answers with the chosen button.

import FormatsTesting
import Foundation
import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
@testable import OpenSkyScriptingInterface
import Testing

@MainActor
struct CameraShake {
    let strength: Float
    let duration: Float
}

final class FakePresenter: PapyrusPresenting {
    var notifications: [String] = []
    var boxes: [String] = []
    var shown: [(ReferenceKey, [Float])] = []
    var help: [PapyrusHelpMessageRequest] = []
    var resets: [String] = []
    var shakes: [CameraShake] = []
    var cameraModes: [Bool] = []
    var showResult = PapyrusMessageShowResult.awaitingButton(token: 9)

    func postNotification(_ text: String) -> Bool {
        notifications.append(text)
        return true
    }

    func showMessage(_ message: ReferenceKey, arguments: [Float]) -> PapyrusMessageShowResult {
        shown.append((message, arguments))
        return showResult
    }

    func showMessageBox(_ text: String) -> Bool {
        boxes.append(text)
        return true
    }

    func showHelpMessage(_ request: PapyrusHelpMessageRequest) -> Bool {
        help.append(request)
        return true
    }

    func resetHelpMessage(event: String) {
        resets.append(event)
    }

    func shakeCamera(source: ReferenceKey?, strength: Float, duration: Float) -> Bool {
        shakes.append(CameraShake(strength: strength, duration: duration))
        return true
    }

    func forceCameraMode(firstPerson: Bool) -> Bool {
        cameraModes.append(firstPerson)
        return true
    }
}

@MainActor
struct PapyrusNativePresentationTests {
    private static func call(
        _ script: String,
        _ function: String,
        receiver: PapyrusObjectHandle? = nil,
        arguments: [PapyrusValue] = [],
        returnType: PapyrusType = .none
    ) -> PapyrusNativeCall {
        PapyrusWorldFixture.methodCall(
            script, function, receiver: receiver, arguments: arguments, returnType: returnType
        )
    }

    private static func fixture() throws -> (PapyrusNativeReferenceFixture, FakePresenter) {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let presenter = FakePresenter()
        fixture.session.bridge.presenter = presenter
        return (fixture, presenter)
    }

    @Test func notificationAndMessageBoxReachThePresenter() throws {
        let (fixture, presenter) = try Self.fixture()
        #expect(fixture.registry.invoke(Self.call(
            "Debug",
            "Notification",
            arguments: [.string("Hi")]
        ))
            == .returned(.none))
        #expect(fixture.registry.invoke(Self.call(
            "Debug",
            "MessageBox",
            arguments: [.string("Box")]
        ))
            == .returned(.none))
        #expect(presenter.notifications == ["Hi"])
        #expect(presenter.boxes == ["Box"])
    }

    @Test func showPassesNineNumbersAndWaitsForTheButton() throws {
        let (fixture, presenter) = try Self.fixture()
        let result = fixture.registry.invoke(Self.call(
            "Message", "Show", receiver: fixture.receiver,
            arguments: [.float(1), .integer(2)], returnType: .integer
        ))
        #expect(result == .suspended(.external(9)))
        #expect(presenter.shown.first?.0 == fixture.key)
        #expect(presenter.shown.first?.1 == [1, 2, 0, 0, 0, 0, 0, 0, 0])
        presenter.showResult = .posted
        #expect(fixture.registry.invoke(Self.call(
            "Message", "Show", receiver: fixture.receiver, returnType: .integer
        )) == .returned(.integer(-1)))
    }

    @Test func helpMessagesAndCameraCallsReachThePresenter() throws {
        let (fixture, presenter) = try Self.fixture()
        _ = fixture.registry.invoke(Self.call(
            "Message", "ShowAsHelpMessage", receiver: fixture.receiver,
            arguments: [.string("Jump"), .float(5), .float(30), .integer(3)]
        ))
        _ = fixture.registry.invoke(Self.call(
            "Message",
            "ResetHelpMessage",
            arguments: [.string("Jump")]
        ))
        _ = fixture.registry.invoke(Self.call("Game", "ShakeCamera", arguments: [.none]))
        _ = fixture.registry.invoke(Self.call("Game", "ForceThirdPerson"))
        #expect(presenter.help == [PapyrusHelpMessageRequest(
            message: fixture.key, event: "Jump", duration: 5, interval: 30, maxTimes: 3
        )])
        #expect(presenter.resets == ["Jump"])
        #expect(presenter.shakes.first?.strength == 0.5)
        #expect(presenter.shakes.first?.duration == 0)
        #expect(presenter.cameraModes == [false])
    }

    @Test func withoutAPresenterTheMessageNativesFail() throws {
        let fixture = try PapyrusNativeReferenceFixture.make()
        let result = fixture.registry.invoke(Self.call(
            "Message", "Show", receiver: fixture.receiver, returnType: .integer
        ))
        #expect(PapyrusWorldFixture.isInvalidArguments(result))
        #expect(fixture.registry.invoke(Self.call(
            "Debug",
            "Notification",
            arguments: [.string("x")]
        ))
            == .returned(.none))
    }

    @Test func scriptResumesWithTheAnswer() {
        struct AskDispatch: PapyrusNativeDispatch {
            func invoke(_: PapyrusNativeCall) -> PapyrusNativeResult {
                .suspended(.external(5))
            }
        }
        let run = PexFixture.runtimeFunction(
            returnType: "Int",
            locals: [PexTypedName(name: "answer", typeName: "Int")],
            instructions: [
                PapyrusTestSupport.instruction(
                    .callStatic, .identifier("Debug"), .identifier("Ask"), .identifier("answer"),
                    .integer(0)
                ),
                PapyrusTestSupport.instruction(
                    .integerAdd, .identifier("answer"), .identifier("answer"), .integer(10)
                ),
                PapyrusTestSupport.instruction(.returnValue, .identifier("answer"))
            ]
        )
        let script = PexFixture.runtimeObject(
            name: "Asker", states: [PapyrusTestSupport.state(functions: [("Run", run)])]
        )
        let (runtime, handle) = PapyrusTestSupport.runtime(
            objects: [script],
            nativeDispatch: AskDispatch()
        )
        let scheduler = PapyrusScheduler(runtime: runtime, fixedStepSeconds: 1)
        scheduler.schedule(runtime.invoke("Run", on: handle))
        #expect(scheduler.waitingTokens == [5])
        #expect(scheduler.tick().isEmpty)
        #expect(!scheduler.answer(6, returning: .integer(1)))
        #expect(scheduler.answer(5, returning: .integer(2)))
        let outcomes = scheduler.tick()
        #expect(outcomes.compactMap(PapyrusTestSupport.value) == [.integer(12)])
        #expect(scheduler.waitingTokens.isEmpty)
    }
}
