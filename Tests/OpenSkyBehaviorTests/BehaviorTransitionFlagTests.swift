// Pins the transition flag bits to the table in
// docs/engine/behavior-state-machines.md.

import OpenSkyBehavior
import Testing

struct BehaviorTransitionFlagTests {
    @Test func flagBitsMatchTheDocumentedTable() {
        let bits: [(Int, Int)] = [
            (BehaviorTransitionFlag.useTriggerInterval, 0x1),
            (BehaviorTransitionFlag.useInitiateInterval, 0x2),
            (BehaviorTransitionFlag.uninterruptibleWhilePlaying, 0x4),
            (BehaviorTransitionFlag.uninterruptibleWhileBlending, 0x8),
            (BehaviorTransitionFlag.delayStateChange, 0x10),
            (BehaviorTransitionFlag.disabled, 0x20),
            (BehaviorTransitionFlag.disableCondition, 0x100),
            (BehaviorTransitionFlag.allowSelfTransition, 0x200),
            (BehaviorTransitionFlag.globalWildcard, 0x400),
            (BehaviorTransitionFlag.localWildcard, 0x800),
            (BehaviorTransitionFlag.fromNestedStateIsValid, 0x1000),
            (BehaviorTransitionFlag.toNestedStateIsValid, 0x2000)
        ]
        for (flag, documented) in bits {
            #expect(flag == documented)
        }
    }
}
