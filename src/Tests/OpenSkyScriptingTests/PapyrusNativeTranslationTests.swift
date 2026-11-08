// `TranslateTo`, `SplineTranslateTo`, and `StopTranslation` through the bridge: the live
// pose scripts read, the events in order, and the one store write at the end.

import Foundation
@testable import OpenSkyFormatsESM
import OpenSkyFormatsTesting
@testable import OpenSkyScripting
import OpenSkyScriptingFixtures
import OpenSkyScriptingInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
struct PapyrusNativeTranslationTests {
    private static let moverID: UInt32 = 0x2000
    private static let moverKey = ReferenceKey.plugin(
        name: PapyrusWorldFixture.pluginName, objectID: moverID
    )

    private let session: PapyrusWorldFixture.Session
    private let registry: PapyrusNativeRegistry

    init() throws {
        let mover = try PapyrusWorldFixture.referenceEntry(
            objectID: Self.moverID, scripts: [VMADFixture.Script("Mover", properties: [])]
        )
        session = PapyrusWorldFixture.session(
            objects: [PapyrusWorldFixture.eventScript("Mover", events: [
                ("OnTranslationAlmostComplete", PapyrusWorldFixture.probeBody(note: "almost")),
                ("OnTranslationComplete", PapyrusWorldFixture.probeBody(note: "complete")),
                ("OnTranslationFailed", PapyrusWorldFixture.probeBody(note: "failed"))
            ])],
            entries: [mover]
        )
        PapyrusWorldFixture.drain(session.world)
        registry = PapyrusWorldFixture.registry(for: session)
    }

    @discardableResult
    private func call(_ name: String, _ numbers: [Float] = []) -> PapyrusNativeResult {
        registry.invoke(PapyrusWorldFixture.methodCall(
            "ObjectReference", name,
            receiver: session.world.objectHandle(for: Self.moverKey),
            arguments: numbers.map { .float($0) }
        ))
    }

    private func translate(toX x: Float, angleZ: Float = 0) -> PapyrusNativeResult {
        call("TranslateTo", [x, 0, 0, 0, 0, angleZ, 100])
    }

    private func advance(_ seconds: Float) {
        session.bridge.advanceTranslations(by: seconds)
        PapyrusWorldFixture.drain(session.world)
    }

    private func number(_ name: String) -> Float? {
        guard case let .returned(.float(value)) = call(name) else { return nil }
        return value
    }

    private func isNear(_ value: Float?, _ expected: Float) -> Bool {
        value.map { abs($0 - expected) < 0.001 } ?? false
    }

    private var storedTransform: ReferenceTransformOverride? {
        session.worldState.component(ReferenceTransformOverride.self, for: Self.moverKey)
    }

    @Test func scriptsReadTheLivePoseAndTheStoreGetsOnlyTheEnd() {
        #expect(translate(toX: 100, angleZ: 90) == .returned(.none))
        advance(0.5)
        #expect(isNear(number("GetPositionX"), 50))
        #expect(isNear(number("GetAngleZ"), 45))
        #expect(storedTransform == nil)
        #expect(session.bridge.translationPoses[Self.moverKey]?.position.x == 50)

        advance(0.5)
        #expect(storedTransform?.position == SIMD3(100, 0, 0))
        #expect(session.bridge.translations.isEmpty)
        #expect(session.dispatch.notes == ["almost", "complete"])
    }

    @Test func aNewRequestFailsTheRunningMove() {
        _ = translate(toX: 100)
        advance(0.25)
        _ = translate(toX: -100)
        PapyrusWorldFixture.drain(session.world)
        #expect(session.dispatch.notes == ["failed"])
        advance(0.25)
        #expect(isNear(number("GetPositionX"), 0))
    }

    @Test func stopLeavesTheReferenceWhereItIsWithNoEvent() {
        _ = translate(toX: 100)
        advance(0.25)
        call("StopTranslation")
        advance(1)
        #expect(isNear(storedTransform?.position.x, 25))
        #expect(session.dispatch.notes.isEmpty)
    }

    @Test func setPositionEndsTheMove() {
        _ = translate(toX: 100)
        advance(0.25)
        call("SetPosition", [5, 5, 5])
        advance(1)
        #expect(storedTransform?.position == SIMD3(5, 5, 5))
        #expect(session.dispatch.notes.isEmpty)
    }

    @Test func splineMovesInAStraightLineAtItsOwnSpeed() {
        #expect(call("SplineTranslateTo", [100, 0, 0, 0, 0, 0, 3, 200]) == .returned(.none))
        advance(0.25)
        #expect(isNear(number("GetPositionX"), 50))
    }

    @Test func aStillSpeedFails() {
        #expect(PapyrusWorldFixture.isInvalidArguments(call("TranslateTo", [1, 0, 0, 0, 0, 0, 0])))
    }

    @Test func aLoadedGameDropsRunningMoves() {
        var published: [[ReferenceKey: ReferenceTransformOverride]] = []
        session.bridge.sessionNatives.publishTranslationPoses = { published.append($0) }
        _ = translate(toX: 100)
        session.bridge.clearTranslations()
        #expect(published.map(\.count) == [1, 0])
    }
}
