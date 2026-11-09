// `PerkActivationWorldAdapter` joins the started session: what `wire` registered.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyMenus
import OpenSkyProgressionInterface
import OpenSkyScriptingInterface
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// Connects `PerkActivationWorldAdapter` to the started session.
public struct PerkActivationWiring {
    public init(_ adapter: PerkActivationWorldAdapter, streamer: CellStreamer) {
        let coordinator = adapter.game.perkActivation
        streamer.activationGate.perkChoices = { [weak coordinator] target in
            coordinator?.activate(target) ?? false
        }
    }
}
