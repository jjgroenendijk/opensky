// The record stores the adapters read, each adapter through its own records port.
// A base of `SessionPorts`, so the composition root stays below the type size limit.

import OpenSkyActorAdapters
import OpenSkyAIAdapters
import OpenSkyCells
import OpenSkyCombatInterface
import OpenSkyGameData
import OpenSkyMenuAdapters
import OpenSkySessionAdapters

class SessionRecordPorts {
    unowned let scope: GameSessionScope

    init(scope: GameSessionScope) {
        self.scope = scope
    }

    var worldData: WorldDataStores? {
        scope.worldData
    }

    // Each port is boxed once. A fresh box per read copies every store of the set, and
    // the per-frame record reads ask thousands of times.
    private(set) lazy var worldRecords: (any WorldRecordsPort)? = scope.worldData
    private(set) lazy var combatRecords: (any CombatRecordsPort)? = scope.worldData
    private(set) lazy var actorRecords: (any ActorRecordsPort)? = scope.worldData
    private(set) lazy var aiRecords: (any AIRecordsPort)? = scope.worldData
    private(set) lazy var sessionRecords: (any SessionRecordsPort)? = scope.worldData
    private(set) lazy var menuRecords: (any MenuRecordsPort)? = scope.worldData
}
