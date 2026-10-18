// The Survival Mode coordinator reads and writes the plugin's globals through
// the session's global store, as scripts and the Globals panel do.

import OpenSkyMenus
import OpenSkyRuntimeState
import OpenSkyWorldState

final class SurvivalModeWorldAdapter: SurvivalModeWorld {
    private unowned let runtimeState: RuntimeStateCoordinator

    init(runtimeState: RuntimeStateCoordinator) {
        self.runtimeState = runtimeState
    }

    func survivalGlobal(_ editorID: String) -> Float? {
        runtimeState.globalResolution().floatValue(editorID: editorID)
    }

    func setSurvivalGlobal(_ value: Float, editorID: String) {
        runtimeState.setGlobalValue(value, editorID: editorID)
    }
}
