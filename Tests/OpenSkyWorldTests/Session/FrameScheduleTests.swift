// FrameSchedule: phase order wins over registration order, and the declared
// world-tick order is pinned.

import Foundation
import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

@MainActor
struct FrameScheduleTests {
    @Test func anEmptyScheduleIsANoOp() {
        let schedule = FrameSchedule<WorldTickStep, Float>()
        #expect(schedule.isEmpty)
        schedule(1)
    }

    @Test func stepsRunInPhaseOrderNotRegistrationOrder() {
        let schedule = FrameSchedule<WorldTickStep, Float>()
        var order: [WorldTickStep] = []
        schedule.register(.story) { _ in order.append(.story) }
        schedule.register(.scripts) { _ in order.append(.scripts) }
        schedule.register(.packages) { _ in order.append(.packages) }
        schedule(0.5)
        #expect(order == [.scripts, .packages, .story])
        #expect(schedule.registeredPhases == [.scripts, .packages, .story])
    }

    @Test func aLateStepTakesItsOwnSlot() {
        let schedule = FrameSchedule<FrameStep, Int>()
        var order: [String] = []
        schedule.register(.hud) { order.append("hud:\($0)") }
        schedule(1)
        schedule.register(.streaming) { order.append("streaming:\($0)") }
        schedule(2)
        #expect(order == ["hud:1", "streaming:2", "hud:2"])
    }

    /// Moving a case changes the simulation, so a change here must be deliberate.
    @Test func theWorldTickOrderIsPinned() {
        #expect(WorldTickStep.allCases == [
            .survivalMode, .scripts, .actorValues, .magicEffects, .breath, .archery, .ragdoll,
            .combatLoop,
            .packages, .perception, .idles, .actorGraphs, .vehicles, .furniture,
            .objectAnimation, .effectGraphs,
            .dialogueCamera, .story
        ])
    }

    @Test func streamingRunsBeforeTheHUDReadsIt() {
        let order = FrameStep.allCases
        let streaming = order.firstIndex(of: .streaming) ?? order.endIndex
        let hud = order.firstIndex(of: .hud) ?? order.startIndex
        #expect(streaming < hud)
        #expect(order.firstIndex(of: .melee) ?? 0 < order.firstIndex(of: .ragdoll) ?? 0)
    }

    @Test func meleeRunsBeforeTheActorStateGraphReadsIt() {
        let order = FrameStep.allCases
        let melee = order.firstIndex(of: .melee) ?? order.endIndex
        let actorState = order.firstIndex(of: .actorState) ?? order.startIndex
        #expect(melee < actorState)
    }
}
