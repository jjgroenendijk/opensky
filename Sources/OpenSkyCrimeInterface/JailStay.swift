// One stay in jail, from the door into the cell to release or escape. UESP
// "Skyrim:Crime", Going to Jail: the bounty stays owed by an escapee, and a sentence
// is served by sleeping in the cell. See docs/engine/jail.md.

import OpenSkyFormatsESM
import OpenSkyGameData

/// The player in a faction's jail.
nonisolated public struct JailStay: Equatable, Sendable {
    public let faction: ReferenceKey
    /// The bounty taken off at the arrest. An escape puts it back.
    public let nonViolentGold: Int32
    public let violentGold: Int32
    public let sentenceDays: Int
    /// The faction's `JAIL` PrisonMarker door outside; its `XTEL` leads into the cell.
    public let exteriorMarker: ReferenceKey
    /// The `PLCN` chest that holds the player's belongings, or nil when none is set.
    public let belongings: ReferenceKey?
    /// The `JOUT` pieces given to the player.
    public let outfit: [FormID]
    /// Where the arrest happened. The stay begins once the player is somewhere else.
    public let arrestedIn: CellSceneLocation?
    /// The jail cell, once the player stands in it.
    public private(set) var cell: CellSceneLocation?

    public init(
        faction: ReferenceKey, nonViolentGold: Int32, violentGold: Int32, sentenceDays: Int,
        exteriorMarker: ReferenceKey, belongings: ReferenceKey?, outfit: [FormID],
        arrestedIn: CellSceneLocation?
    ) {
        self.faction = faction
        self.nonViolentGold = nonViolentGold
        self.violentGold = violentGold
        self.sentenceDays = sentenceDays
        self.exteriorMarker = exteriorMarker
        self.belongings = belongings
        self.outfit = outfit
        self.arrestedIn = arrestedIn
    }

    /// What the player's cell this tick means for the stay.
    public enum Step: Equatable, Sendable {
        case waiting, arrived, escaped
    }

    /// One tick. The first cell after the arrest cell is the jail; leaving it after
    /// that, by any way but serving, is an escape.
    public mutating func step(playerCell: CellSceneLocation?) -> Step {
        guard let playerCell else { return .waiting }
        guard let cell else {
            guard playerCell != arrestedIn else { return .waiting }
            cell = playerCell
            return .arrived
        }
        return playerCell == cell ? .waiting : .escaped
    }
}
