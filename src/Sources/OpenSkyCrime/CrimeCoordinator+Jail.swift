// The jail stay: belongings into the `PLCN` chest, the `JOUT` outfit on, and the
// player through the `JAIL` door into the cell. Serving the sentence costs skill
// progress and gives everything back; leaving the cell any other way is an escape.
// CK wiki "Creating a Custom Crime Faction" and UESP "Skyrim:Crime". See
// docs/engine/jail.md.

import OpenSkyConditions
public import OpenSkyCrimeInterface
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface

extension CrimeCoordinator {
    /// Starts a stay for a sentence. False when there is no sentence, no `JAIL`
    /// door, or the door cannot be entered; then the sentence is served at once.
    func imprison(_ settlement: ArrestSettlement, owed: CrimeLedgerEntry?) -> Bool {
        guard
            settlement.sentenceDays > 0, let marker = settlement.releaseMarker,
            let arrest = crimeArrest()
        else { return false }
        let arrestedIn = world.currentCellLocation
        guard world.enterJail(through: marker) else { return false }
        let belongings = arrest.belongingsChest(of: settlement.faction)
        if let belongings {
            world.storeBelongings(in: belongings, keeping: world.lockpickItem)
        }
        let outfit = arrest.jailOutfit(of: settlement.faction).map(world.wearJailOutfit) ?? []
        jailStay = JailStay(
            faction: settlement.faction,
            nonViolentGold: owed?.nonViolentGold ?? settlement.bounty,
            violentGold: owed?.violentGold ?? 0,
            sentenceDays: settlement.sentenceDays,
            exteriorMarker: marker,
            belongings: belongings,
            outfit: outfit,
            arrestedIn: arrestedIn
        )
        return true
    }

    /// Papyrus `Game.ClearPrison`: the game no longer counts the player as jailed, so
    /// leaving the cell is not an escape (<https://ck.uesp.net/wiki/ClearPrison_-_Game>).
    public func clearPrison() {
        jailStay = nil
    }

    /// One tick: notes the arrival in the cell, and an escape once the player leaves it.
    public func advanceJail() {
        guard var stay = jailStay else { return }
        let escaped = stay.escapes(playerCell: world.currentCellLocation)
        jailStay = stay
        if escaped {
            escape(stay)
        }
    }

    /// `Game.ServeTime`, and sleeping in the cell: the days pass, skills lose
    /// progress, and the player leaves in their own clothes.
    @discardableResult
    public func serveSentence() -> Bool {
        guard let stay = jailStay else { return false }
        jailStay = nil
        world.passGameTime(days: stay.sentenceDays)
        let skills = world.loseJailProgress(
            days: stay.sentenceDays,
            maximumDays: reporter?.runtime.settings.maximumJailDays ?? stay.sentenceDays
        )
        world.returnBelongings(of: stay)
        let moved = world.leaveJail(to: stay.exteriorMarker)
            || world.movePlayer(toMarker: stay.exteriorMarker)
        pendingCommands.append(.incrementStat("Days Jailed", by: Int32(stay.sentenceDays)))
        storyEvents?.reportServedTime(stay)
        lastGuard = .served(
            days: stay.sentenceDays, skills: skills, faction: factionName(stay.faction),
            moved: moved
        )
        return true
    }

    /// The bounty taken at the arrest is owed again, with the faction's escape price.
    func escape(_ stay: JailStay) {
        jailStay = nil
        guard let reporter else { return }
        reporter.modifyCrimeGold(by: stay.violentGold, violent: true, of: stay.faction)
        reporter.modifyCrimeGold(by: stay.nonViolentGold, violent: false, of: stay.faction)
        let price = reporter.reportEscape(from: stay.faction).gold
        let gold = stay.violentGold + stay.nonViolentGold + price
        storyEvents?.reportEscape(stay)
        pendingCommands.append(.incrementStat("Jail Escapes", by: 1))
        // The escape price shows its own notice as it is charged.
        showBountyNotice(
            gold: stay.violentGold + stay.nonViolentGold, added: true, faction: stay.faction
        )
        lastGuard = .escaped(gold: gold, faction: factionName(stay.faction))
        refreshGuardHostility()
    }
}

extension CrimeCoordinator {
    /// A stay a save brought back. The jail cell is found again from the player's cell.
    public func restoreJailStay(_ stay: JailStay?) {
        jailStay = stay
    }
}

extension StoryEventReporting {
    func reportServedTime(_ stay: JailStay) {
        reportStoryEvent(.servedTime(
            location: nil, crimeFaction: stay.faction,
            gold: stay.nonViolentGold + stay.violentGold, days: stay.sentenceDays
        ))
    }

    func reportEscape(_ stay: JailStay) {
        reportStoryEvent(.escapeJail(location: nil, crimeFaction: stay.faction))
    }
}

nonisolated extension JailStay {
    /// One tick of `step`: true when the player has just left the jail cell.
    mutating func escapes(playerCell: CellSceneLocation?) -> Bool {
        step(playerCell: playerCell) == .escaped
    }
}
