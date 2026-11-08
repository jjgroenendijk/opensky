// The Survival Mode coordinator reads and writes the plugin's globals through
// the session's global store, as scripts and the Globals readout do.

public import OpenSkyMenus
public import OpenSkyRuntimeState
import OpenSkyWorldState

public final class SurvivalModeWorldAdapter: SurvivalModeWorld {
    private unowned let runtimeState: RuntimeStateCoordinator

    public init(runtimeState: RuntimeStateCoordinator) {
        self.runtimeState = runtimeState
    }

    public func survivalGlobal(_ editorID: String) -> Float? {
        runtimeState.globalResolution().floatValue(editorID: editorID)
    }

    public func setSurvivalGlobal(_ value: Float, editorID: String) {
        runtimeState.setGlobalValue(value, editorID: editorID)
    }
}
