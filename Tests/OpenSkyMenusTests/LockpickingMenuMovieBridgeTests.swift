// The lockpicking movie bridge: the panel values and the debug angles it sends.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyInventoryInterface
@testable import OpenSkyMenus
import Testing

@MainActor
struct LockpickingMenuMovieBridgeTests {
    @Test func theLockInfoCarriesSkillLevelAndPicks() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let log = MenuMovieCallLog(runtime: runtime, names: ["SetLockInfo"])
        let info = LockpickingMovieInfo(
            skillLevel: 31, skillProgress: 0.25, lockLevel: "Adept", picksRemaining: 4
        )
        LockpickingMenuMovieBridge.publish(info, runtime: runtime)
        #expect(log.arguments(of: "SetLockInfo") == [
            .integer(31), .integer(32), .number(25), .string("Adept"), .integer(4)
        ])
    }

    @Test func aFrameSendsAnglesInDegreesAndHealthInPercent() throws {
        let runtime = try MenuMovieCallLog.emptyRuntime()
        let log = MenuMovieCallLog(
            runtime: runtime, names: ["UpdatePickAngle", "UpdateLockAngle", "UpdatePickHealth"]
        )
        let frame = LockpickingMenuPresentation(
            title: "Door", difficulty: .adept, pickAngle: -30, halfArc: 90,
            lockRotation: 0.5, pickHealth: 0.75, picksRemaining: 4, isStraining: false
        )
        LockpickingMenuMovieBridge.publish(frame, runtime: runtime)
        #expect(log.arguments(of: "UpdatePickAngle") == [.number(-30)])
        #expect(log.arguments(of: "UpdateLockAngle") == [.number(45)])
        #expect(log.arguments(of: "UpdatePickHealth") == [.number(75)])
    }
}
