// Raises the day stats once for each clock move that passed midnight.
// See docs/engine/statistics.md, Days.

import OpenSkyFormatsESM
public import OpenSkyGameData
import OpenSkyQuestsInterface
public import OpenSkySessionInterface
import OpenSkyWorldInterface
import OpenSkyWorldState

/// What `MiscStatsDaysAdapter` reads from the session.
@MainActor
public protocol MiscStatsDaysHost: AnyObject, SendableMetatype {
    var gameSession: (any GameSessionPort)? { get }
    var runtimeState: any RuntimeStatePort { get }
    var worldRecords: (any WorldRecordsPort)? { get }
    var worldState: any WorldStateStorePort { get }
}

public struct MiscStatsDaysAdapter {
    public let game: any MiscStatsDaysHost

    public init(game: any MiscStatsDaysHost) {
        self.game = game
    }

    /// The globals are read when the day passes, as the game reads them.
    public func tick() {
        guard let gameSession = game.gameSession else { return }
        let days = gameSession.gameTime.consumeDaysPassed()
        guard days > 0 else { return }
        let sources = game.worldRecords?.miscStatSources ?? MiscStatSources()
        let globals = game.runtimeState.globalResolution()
        func isSet(_ global: FormID?) -> Bool {
            global.flatMap { globals.floatValue(for: $0) }.map { $0 != 0 } ?? false
        }
        let stats = MiscStats.dayPassed(
            isVampire: isSet(sources.playerIsVampire),
            isWerewolf: isSet(sources.playerIsWerewolf)
        )
        for stat in stats {
            game.worldState.incrementMiscStat(stat, by: Int32(days))
        }
    }
}
