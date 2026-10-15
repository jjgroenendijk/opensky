// The pure move behind `TranslateTo`: travel at the given speed, rotation that arrives with
// the position unless a cap slows it, and the one almost-complete step.

import Foundation
@testable import OpenSkyScripting
import Testing

struct PapyrusTranslationTests {
    private static func move(
        to target: SIMD3<Float> = SIMD3(100, 0, 0),
        rotation: SIMD3<Float> = .zero,
        speed: Float = 100,
        cap: Float = 0
    ) throws -> PapyrusTranslation {
        try #require(PapyrusTranslation(
            from: .zero, rotation: .zero, to: target, rotation: rotation,
            speed: speed, maxRotationSpeed: cap
        ))
    }

    @Test func travelsAtTheGivenSpeed() throws {
        var move = try Self.move()
        #expect(move.advance(by: 0.5) == .moving)
        #expect(abs(move.position.x - 50) < 0.001)
    }

    @Test func signalsAlmostCompleteOnceThenCompletesAtTheTarget() throws {
        var move = try Self.move()
        let steps = (0 ..< 10).map { _ in move.advance(by: 0.125) }
        #expect(steps.filter { $0 == .almostComplete }.count == 1)
        #expect(steps.firstIndex(of: .almostComplete) == 5)
        #expect(steps.firstIndex(of: .complete) == 7)
        #expect(move.position == SIMD3(100, 0, 0))
    }

    @Test func rotationArrivesWithThePositionWithoutACap() throws {
        var move = try Self.move(rotation: SIMD3(0, 0, 1))
        _ = move.advance(by: 0.5)
        #expect(abs(move.rotation.z - 0.5) < 0.001)
        #expect(move.advance(by: 0.5) == .complete)
        #expect(move.rotation.z == 1)
    }

    @Test func aRotationCapKeepsTurningAfterThePositionArrives() throws {
        var move = try Self.move(rotation: SIMD3(0, 0, 1), cap: 0.5)
        #expect(move.advance(by: 1) != .complete)
        #expect(move.position == SIMD3(100, 0, 0))
        #expect(abs(move.rotation.z - 0.5) < 0.001)
        #expect(move.advance(by: 1) == .complete)
        #expect(move.rotation.z == 1)
    }

    @Test func turnsTheShortWayAround() throws {
        var move = try #require(PapyrusTranslation(
            from: .zero, rotation: SIMD3(0, 0, 3), to: SIMD3(100, 0, 0),
            rotation: SIMD3(0, 0, -3), speed: 100
        ))
        _ = move.advance(by: 0.5)
        #expect(move.rotation.z > 3)
    }

    @Test func refusesAStillOrBrokenRequest() {
        #expect(PapyrusTranslation(
            from: .zero, rotation: .zero, to: .one, rotation: .zero, speed: 0
        ) == nil)
        #expect(PapyrusTranslation(
            from: .zero, rotation: .zero, to: SIMD3(.nan, 0, 0), rotation: .zero, speed: 1
        ) == nil)
    }
}
