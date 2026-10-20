// The jail stay: belongings into the `PLCN` chest, the `JOUT` outfit on, and the
// player through the `JAIL` door into the cell. Serving the sentence costs skill
// progress and gives everything back; leaving the cell any other way is an escape.
// CK wiki "Creating a Custom Crime Faction" and UESP "Skyrim:Crime". See
// docs/engine/jail.md.

import OpenSkyConditions
import OpenSkyCrimeInterface
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
            moveAll(from: .player, to: chestHolder(belongings), keeping: world.lockpickItem)
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

    /// One tick: notes the arrival in the cell, and an escape once the player leaves it.
    public func advanceJail() {
        guard var stay = jailStay else { return }
        let step = stay.step(playerCell: world.currentCellLocation)
        jailStay = stay
        if step == .escaped {
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
        giveBack(stay)
        let moved = world.leaveJail(to: stay.exteriorMarker)
            || world.movePlayer(toMarker: stay.exteriorMarker)
        pendingCommands.append(.incrementStat("Days Jailed", by: Int32(stay.sentenceDays)))
        storyEvents?.reportStoryEvent(.servedTime(
            location: nil, crimeFaction: stay.faction,
            gold: stay.nonViolentGold + stay.violentGold, days: stay.sentenceDays
        ))
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
        let price = reporter.runtime.prices(of: stay.faction)?.escape
            ?? reporter.runtime.settings.defaultPrices.escape
        reporter.modifyCrimeGold(by: stay.violentGold, violent: true, of: stay.faction)
        reporter.modifyCrimeGold(by: stay.nonViolentGold + price, violent: false, of: stay.faction)
        let gold = stay.violentGold + stay.nonViolentGold + price
        storyEvents?.reportStoryEvent(.escapeJail(location: nil, crimeFaction: stay.faction))
        pendingCommands.append(.incrementStat("Jail Escapes", by: 1))
        showBountyNotice(gold: gold, added: true, faction: stay.faction)
        lastGuard = .escaped(gold: gold, faction: factionName(stay.faction))
        refreshGuardHostility()
    }

    // MARK: - Private

    private func giveBack(_ stay: JailStay) {
        guard let inventory = world.inventory else { return }
        for piece in stay.outfit where inventory.count(of: piece, in: .player) > 0 {
            _ = try? inventory.remove(piece, count: 1, from: .player)
        }
        if let belongings = stay.belongings {
            moveAll(from: chestHolder(belongings), to: .player, keeping: nil)
        }
    }

    /// Every stack but one of `kept` moves; a failed move leaves the stack where it is.
    private func moveAll(
        from source: InventoryHolder,
        to target: InventoryHolder,
        keeping kept: FormID?
    ) {
        guard let inventory = world.inventory else { return }
        var keptOne = false
        for stack in inventory.inventory(of: source).stacks {
            var count = stack.count
            if stack.item == kept, !keptOne {
                keptOne = true
                count -= 1
            }
            guard count > 0, (try? inventory.remove(stack.item, count: count, from: source)) != nil
            else { continue }
            _ = try? inventory.add(stack.item, count: count, to: target)
        }
    }
}
