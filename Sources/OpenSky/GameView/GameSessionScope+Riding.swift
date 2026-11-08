// The riding and flight settings the session's mount and flight coordinators start with.

import OpenSkyActorPresentation
import OpenSkyCells
import OpenSkyMenuAdapters
import OpenSkyPlayer
import OpenSkyWorldInterface

extension GameSessionScope {
    var mountSettings: MountSettings {
        worldData.map { data in
            MountSettings.resolve(store: data.gameSettings) { [unowned self] in mapWorld.text($0) }
        } ?? .vanilla
    }

    var dragonFlightSettings: DragonFlightSettings {
        worldData?.dragonFlightSettings ?? .standard
    }
}
