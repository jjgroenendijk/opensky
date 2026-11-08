// Menu time for `PapyrusWorldRuntime`. A menu pauses the world and every script wait
// but `WaitMenuMode`, which counts menu time too (CK wiki "WaitMenuMode - Utility").

import Foundation
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime {
    /// Runs whole fixed steps of menu time, at most `maximumStepsPerAdvance`. Only
    /// `WaitMenuMode` waits move and resume; events and timers wait for the world.
    @discardableResult
    public func advanceMenuTime(delta: Float) -> Int {
        guard !isPaused, delta > 0 else { return 0 }
        menuAccumulatorSeconds += Double(delta)
        var steps = 0
        while menuAccumulatorSeconds >= fixedStepSeconds, steps < Self.maximumStepsPerAdvance {
            menuAccumulatorSeconds -= fixedStepSeconds
            stepMenuTime()
            steps += 1
        }
        menuAccumulatorSeconds = min(
            menuAccumulatorSeconds, fixedStepSeconds * Double(Self.maximumStepsPerAdvance)
        )
        return steps
    }

    /// One fixed step of menu time under the same instruction budget as a world step.
    public func stepMenuTime() {
        let natives = (runtime.nativeDispatch as? PapyrusNativeRegistry)?.context
        runtime.stepInstructionsLeft = max(0, budget.instructions)
        natives?.isInMenuMode = true
        defer {
            runtime.stepInstructionsLeft = .max
            natives?.isInMenuMode = false
        }
        _ = scheduler.tickMenu()
        _ = suspensionTracker.drainStep()
    }
}
