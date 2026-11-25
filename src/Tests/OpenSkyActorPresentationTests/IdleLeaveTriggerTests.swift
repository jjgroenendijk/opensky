// A rider without a live graph leaves a cart exit state when the clip's leaving trigger
// fires, not when the clip ends. Seat B's exit clip is 11 s, its trigger at 9 s.

import OpenSkyBehavior
import OpenSkyWorldInterface
import Testing

struct IdleLeaveTriggerTests {
    private static let leave = BehaviorClipTriggerEvent(
        name: "OffsetBoundStandingCartStart", time: 9, fromEnd: false
    )

    @Test func theIdleEndsAtTheEarliestLeavingTrigger() {
        var plan = IdlePlaybackPlan(
            event: "IdleCartPrisonerBExit", path: .namedClip, clipPath: "exit.hkx", prop: .none
        )
        #expect(plan.leaveTime(clipDuration: 11) == nil)
        plan.leavingTriggers = [
            Self.leave, BehaviorClipTriggerEvent(name: "Late", time: -0.5, fromEnd: true)
        ]
        #expect(plan.leaveTime(clipDuration: 11) == 9)
        #expect(plan.leaveTime(clipDuration: 11, before: 9) == nil)
    }

    @Test func aTriggerFromTheEndCountsFromTheClipEnd() {
        var plan = IdlePlaybackPlan(
            event: "IdleCartDriverExit", path: .namedClip, clipPath: "exit.hkx", prop: .none
        )
        plan.leavingTriggers = [BehaviorClipTriggerEvent(
            name: "CartExit",
            time: -0.2,
            fromEnd: true
        )]
        let time = plan.leaveTime(clipDuration: 5.67)
        #expect(time.map { abs($0 - 5.47) < 0.001 } == true)
    }
}
