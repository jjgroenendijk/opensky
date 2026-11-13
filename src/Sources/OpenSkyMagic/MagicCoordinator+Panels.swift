// The Magic Effects and Spellcasting readouts, read off the runtimes
// `MagicCoordinator` owns. Every action returns the sentence the readout shows.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface

extension MagicCoordinator.ControlPanels {}

extension MagicCoordinator.ControlPanels {
    var castingControlSnapshot: CastingControlSnapshot {
        guard coordinator.caster != nil else { return .unavailable }
        var snapshot = CastingControlSnapshot(
            conditionLines: coordinator.conditionReads.magicConditionLines()
        )
        snapshot.runeText = coordinator.runePlacement.runeText
        snapshot.commandedText = commandedText
        snapshot.castingCueText = coordinator.castingCues.castingCueText
        return snapshot
    }

    @discardableResult
    func readSpellTome(_ item: FormID, spell: FormID) -> CastingActionOutcome {
        guard let caster = coordinator.caster
        else { return coordinator.recordCasting(.unavailable) }
        let spells = caster.spellbook.spells
        let plugin = coordinator.spellPluginName ?? coordinator.pluginName
        let bookKey = spells.resolvedID(item, fromPlugin: plugin)
            .map(ReferenceKey.init(resolved:))
        let spellKey = spells.resolvedID(spell, fromPlugin: plugin)
            .map(ReferenceKey.init(resolved:))
        guard let bookKey else {
            return coordinator.recordCasting(.unresolvedTome(
                book: itemName(item),
                plugin: plugin
            ))
        }
        let reading = caster.spellbook.read(book: bookKey, teaching: spellKey, on: .player)
        let known = caster.spellbook.knownSpells(of: .player).first { $0.key == spellKey }
        if let known, reading.taught {
            coordinator.world.announceSpellLearned(known.displayName)
        } else if let known {
            let lead = coordinator.texts.magic.word("sAlreadyKnown", or: "You already know")
            return coordinator.recordCasting(.spellAlreadyKnown(
                notice: "\(lead) \(known.displayName)."
            ))
        }
        return coordinator.recordCasting(.readTome(reading, book: itemName(item)))
    }

    @discardableResult
    func selectNextKnownSpell() -> CastingActionOutcome {
        let known = playerKnownSpells()
        guard !known.isEmpty else { return coordinator.recordCasting(.noSpellsKnown) }
        coordinator.castingState.selection = MagicCore.nextSelection(
            after: coordinator.castingState.selection,
            count: known.count
        )
        return coordinator
            .recordCasting(.selected(spell: known[coordinator.castingState.selection].displayName))
    }

    @discardableResult
    func readySelectedSpell(in hand: SpellHand) -> CastingActionOutcome {
        guard let caster = coordinator.caster
        else { return coordinator.recordCasting(.unavailable) }
        guard let spell = selectedKnownSpell()
        else { return coordinator.recordCasting(.noSpellSelected) }
        do {
            let change = try caster.spellbook.equip(
                spell.key, in: hand, on: .player,
                inventory: coordinator.world.inventory == nil ? nil : .player
            )
            return coordinator.recordCasting(.readied(
                change, spell: spell.displayName, unequipped: change.unequippedItems.map(itemName)
            ))
        } catch {
            return coordinator.recordCasting(.readyFailed(
                spell: spell.displayName, reason: String(describing: error)
            ))
        }
    }

    /// Fast-forwards the charge, then the maintenance floor, so one press is
    /// one whole cast. Held buttons reach the same states over real frames.
    @discardableResult
    func castReadiedSpell(in hand: SpellHand) -> CastingActionOutcome {
        guard let caster = coordinator.caster
        else { return coordinator.recordCasting(.unavailable) }
        let outcome = caster.begin(hand, on: .player)
        if let failure = outcome.failure {
            return coordinator.recordCasting(.cast(.failed(failure)))
        }
        let charge = caster.state(of: hand).phase == .charging ? MagicCore.panelChargeStep : 0
        caster.advance(delta: charge, on: .player)
        if caster.phase(of: hand) == .concentrating {
            caster.advance(delta: 1, on: .player)
        }
        return coordinator.recordCasting(.cast(caster.release(hand, on: .player)))
    }

    // MARK: - Reads

    func playerKnownSpells() -> [ResolvedSpell] {
        coordinator.caster?.spellbook.knownSpells(of: .player) ?? []
    }

    func selectedKnownSpell() -> ResolvedSpell? {
        let known = playerKnownSpells()
        guard !known.isEmpty else { return nil }
        return known[MagicCore.clampedSelection(
            coordinator.castingState.selection,
            count: known.count
        )]
    }

    private func itemName(_ item: FormID) -> String {
        coordinator.world.itemName(item)
    }
}

extension MagicCoordinator.ControlPanels {
    /// The readout line: who the player commands, against the limit, and who is fading.
    var commandedText: String {
        let mine = coordinator.commanded.filter { $0.caster == .player }
        let names = mine.compactMap { coordinator.world.actorValueHolder(for: $0.actor) }
            .map(coordinator.world.actorName)
        let list = names.isEmpty ? "" : ": " + names.joined(separator: ", ")
        let fading = coordinator.summonCommands.summonFades.values
            .map { "\(Int(($0 * 100).rounded()))%" }.sorted()
        let fades = fading.isEmpty ? "" : "; fading \(fading.joined(separator: ", "))"
        let limit = coordinator.summonCommands.commandLimit(of: .player)
        return "Commanded: \(mine.count) of \(limit)\(list)\(fades)"
    }
}
