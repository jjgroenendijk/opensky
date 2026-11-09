// `BeastFormWorldAdapter` joins the started session: what `wire` registered.

import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyPlayer
import OpenSkyRenderCore
import OpenSkyScriptingInterface
import OpenSkySessionInterface
import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState

/// After the mount gate, so a rider hears the door refusal first.
public struct BeastFormWiring {
    public init(_ adapter: BeastFormWorldAdapter) {
        let streamer = adapter.game.streamer
        streamer.activationGate.register(.beastForm) { [weak adapter] target in
            guard let adapter else { return nil }
            let canTake = adapter.playerRace?.flags.contains(.canPickUpItems) ?? true
            return adapter.form.refusal(for: target.interaction.action, raceCanPickUpItems: canTake)
        }
    }
}
