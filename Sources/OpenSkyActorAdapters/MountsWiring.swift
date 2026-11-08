// `MountWorldAdapter` joins the started session: what `wireMounts` registered.

import OpenSkyActorPresentation
import OpenSkyActorsInterface
import OpenSkyAIPackages
import OpenSkyCells
import OpenSkyCombat
import OpenSkyCombatInterface
import OpenSkyConditions
import OpenSkyCrime
import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMenus
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyProgressionInterface
import OpenSkyRendering
import OpenSkyScripting
import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface
import OpenSkyWorldState
import simd

/// After the locks, whose activation gate this one wraps.
public struct MountsWiring {
    public init(_ adapter: MountWorldAdapter, gameSession: GameSession) {
        gameSession.playerMount = adapter
        guard let streamer = adapter.game.streamer else { return }
        streamer.activationGate.register(.mount) { [weak adapter] target in
            adapter?.mounts.isActive == true && target.interaction.action == .open ? .mounted : nil
        }
        streamer.activationGate.refusals.register(.mount) { [weak adapter] event in
            guard let adapter, event.refusal == .mounted else { return }
            _ = adapter.game.messages.postNotification(adapter.mounts.settings.doorRefusal)
        }
    }
}
