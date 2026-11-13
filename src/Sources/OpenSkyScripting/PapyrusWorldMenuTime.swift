// Menu time for `PapyrusWorldRuntime`. A menu pauses the world and every script wait
// but `WaitMenuMode`, which counts menu time too (CK wiki "WaitMenuMode - Utility").

import Foundation
import OpenSkyScriptingInterface

extension PapyrusWorldRuntime.Timers {
    /// Runs whole fixed steps of menu time, at most `maximumStepsPerAdvance`. Only
    /// `WaitMenuMode` waits move and resume; events and timers wait for the world.
    @discardableResult
    public func advanceMenuTime(delta: Float) -> Int {
        guard !world.isPaused, delta > 0 else { return 0 }
        world.menuAccumulatorSeconds += Double(delta)
        var steps = 0
        while
            world.menuAccumulatorSeconds >= world.fixedStepSeconds,
            steps < PapyrusWorldRuntime.maximumStepsPerAdvance
        {
            world.menuAccumulatorSeconds -= world.fixedStepSeconds
            stepMenuTime()
            steps += 1
        }
        world.menuAccumulatorSeconds = min(
            world.menuAccumulatorSeconds,
            world.fixedStepSeconds * Double(PapyrusWorldRuntime.maximumStepsPerAdvance)
        )
        return steps
    }

    /// One fixed step of menu time under the same instruction budget as a world step.
    public func stepMenuTime() {
        let natives = (world.runtime.nativeDispatch as? PapyrusNativeRegistry)?.context
        world.runtime.stepInstructionsLeft = max(0, world.budget.instructions)
        natives?.isInMenuMode = true
        defer {
            world.runtime.stepInstructionsLeft = .max
            natives?.isInMenuMode = false
        }
        _ = world.scheduler.tickMenu()
        _ = world.suspensionTracker.drainStep()
    }
}
