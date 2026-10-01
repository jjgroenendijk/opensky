// The Magic Effects and Spellcasting panels, read off the runtimes
// `MagicCoordinator` owns. Every action returns the sentence the panel shows.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyWorldState

extension MagicCoordinator: MagicEffectControlProviding {
    public var magicEffectControlSnapshot: MagicEffectControlSnapshot {
        guard let runtime = effects else { return .unavailable }
        let tally = runtime.tally
        let nearest = world?.nearestActorValueHolder()
        return MagicEffectControlSnapshot(
            isAvailable: true,
            playerEffects: runtime.active(on: .player).map { readout(of: $0, runtime: runtime) },
            nearestActorName: nearest.map { world?.actorName($0) ?? $0.key.description },
            nearestActorEffects: nearest.map { holder in
                runtime.active(on: holder).map { readout(of: $0, runtime: runtime) }
            } ?? [],
            runtimeActorCount: runtime.store.snapshot().entries.count { entry in
                entry.delta.component(ActiveEffectState.self) != nil
            },
            appliedCount: tally.applied,
            instantCount: tally.instantApplications,
            expiredCount: tally.expired,
            dispelledCount: tally.dispelled,
            skippedCount: tally.totalSkips,
            unimplementedLines: tally.unimplementedArchetypes.map { entry in
                "\(entry.archetype.description) x\(entry.count)"
            },
            lastActionText: effectActionText
        )
    }

    @discardableResult
    public func consumeFirstCarriedMagicItem() -> String {
        guard effects != nil else {
            effectActionText = MagicCore.effectsUnavailableText
            return effectActionText
        }
        let item = carriedItems { items, item in items.magicItemUse(item) == nil ? nil : item }
            .first
        guard let item else {
            effectActionText = "The player carries nothing to eat or drink."
            return effectActionText
        }
        return consumeMagicItem(item)
    }

    @discardableResult
    public func dispelPlayerMagicEffects() -> String {
        guard let removed = withEffects({ $0.dispelAll(on: .player) }) else {
            effectActionText = MagicCore.effectsUnavailableText
            return effectActionText
        }
        effectActionText = MagicCore.dispelText(removed: removed)
        return effectActionText
    }

    private func readout(
        of effect: ActiveEffect,
        runtime: ActiveEffectRuntime
    ) -> ActiveEffectReadout {
        ActiveEffectReadout(
            name: effectName(effect.effect, runtime: runtime),
            sourceName: effect.source.kind.describedName,
            mode: effect.mode,
            isDetrimental: effect.isDetrimental,
            magnitude: effect.values.first?.magnitude ?? 0,
            duration: effect.duration,
            remaining: effect.remaining,
            valueNames: effect.values.map { ActorValueIdentity.description(of: $0.index) }
        )
    }

    /// Falls back to the key, so a line names something even when the record
    /// left the load order.
    private func effectName(_ key: ReferenceKey, runtime: ActiveEffectRuntime) -> String {
        guard case let .plugin(name, objectID) = key else { return key.description }
        let resolved = ResolvedFormID(plugin: name, objectID: objectID)
        return runtime.effects.effect(resolved)?.displayName ?? key.description
    }
}

extension MagicCoordinator: CastingControlProviding {
    public var castingControlSnapshot: CastingControlSnapshot {
        guard let caster else { return .unavailable }
        let book = caster.spellbook.state(of: .player)
        let tally = caster.tally
        return CastingControlSnapshot(
            isAvailable: true,
            knownSpells: playerKnownSpells().map { readout($0, book: book) },
            selectedSpellName: selectedKnownSpell()?.displayName,
            leftPhase: caster.phase(of: .left),
            rightPhase: caster.phase(of: .right),
            magicka: caster.values.current(of: .player).magicka,
            maximumMagicka: caster.values.maximums(of: .player).magicka,
            carriedTomeNames: carriedSpellTomes().map { itemName($0.item) },
            readBookCount: book.readBooks.count,
            castCount: tally.castCount,
            concentrationSeconds: tally.concentrationSeconds,
            failureCount: tally.failureCount,
            failureLines: tally.failureLines,
            unheldAbilityEntries: tally.unheldAbilityEntries,
            projectileCount: tally.projectileCount,
            deliveryLines: tally.deliveryLines,
            lastHitTargets: lastHit?.targetCount ?? 0,
            lastHitAdjustments: lastHit?.adjustments.map(\.line) ?? [],
            conditionLines: magicConditionLines(),
            lastActionText: castingActionText
        )
    }

    @discardableResult
    public func grantPlayerStartSpells() -> String {
        guard let caster else { return castingUnavailable() }
        let race = caster.spellbook.resolve(world?.playerRaceSpells() ?? [], fromPlugin: pluginName)
        let granted = caster.spellbook.grantStartSpells(to: .player, additional: race)
        let held = caster.applyAbilities(on: .player)
        castingActionText = MagicCore.startSpellsText(granted: granted, held: held)
        return castingActionText
    }

    @discardableResult
    public func readFirstCarriedSpellTome() -> String {
        guard let caster else { return castingUnavailable() }
        guard let tome = carriedSpellTomes().first else {
            castingActionText = "The player carries no spell tome."
            return castingActionText
        }
        let spells = caster.spellbook.spells
        let bookKey = spells.resolvedID(tome.item, fromPlugin: pluginName)
            .map(ReferenceKey.init(resolved:))
        let spellKey = spells.resolvedID(tome.spell, fromPlugin: pluginName)
            .map(ReferenceKey.init(resolved:))
        guard let bookKey else {
            castingActionText = "Could not resolve \(itemName(tome.item)) in \(pluginName)."
            return castingActionText
        }
        let reading = caster.spellbook.read(book: bookKey, teaching: spellKey, on: .player)
        castingActionText = MagicCore.readingText(reading, book: itemName(tome.item))
        return castingActionText
    }

    @discardableResult
    public func selectNextKnownSpell() -> String {
        let known = playerKnownSpells()
        guard !known.isEmpty else {
            castingActionText = "The player knows no spells to select."
            return castingActionText
        }
        selection = MagicCore.nextSelection(after: selection, count: known.count)
        castingActionText = "Selected \(known[selection].displayName)."
        return castingActionText
    }

    @discardableResult
    public func readySelectedSpell(in hand: SpellHand) -> String {
        guard let caster else { return castingUnavailable() }
        guard let spell = selectedKnownSpell() else {
            castingActionText = "No spell selected to ready."
            return castingActionText
        }
        do {
            let change = try caster.spellbook.equip(
                spell.key, in: hand, on: .player, inventory: world?.inventory == nil ? nil : .player
            )
            castingActionText = MagicCore.readyText(
                change, name: spell.displayName, itemNames: change.unequippedItems.map(itemName)
            )
        } catch {
            castingActionText = "Could not ready \(spell.displayName): " + String(describing: error)
        }
        return castingActionText
    }

    /// Fast-forwards the charge, then the maintenance floor, so one press is
    /// one whole cast. Held buttons reach the same states over real frames.
    @discardableResult
    public func castReadiedSpell(in hand: SpellHand) -> String {
        guard let caster else { return castingUnavailable() }
        let outcome = caster.begin(hand, on: .player)
        if let failure = outcome.failure {
            castingActionText = "Cast refused: \(failure.describedReason)"
            return castingActionText
        }
        let charge = caster.state(of: hand).phase == .charging ? MagicCore.panelChargeStep : 0
        caster.advance(delta: charge, on: .player)
        if caster.phase(of: hand) == .concentrating {
            caster.advance(delta: 1, on: .player)
        }
        castingActionText = MagicCore.castText(caster.release(hand, on: .player))
        return castingActionText
    }

    // MARK: - Reads

    func playerKnownSpells() -> [ResolvedSpell] {
        caster?.spellbook.knownSpells(of: .player) ?? []
    }

    func selectedKnownSpell() -> ResolvedSpell? {
        let known = playerKnownSpells()
        guard !known.isEmpty else { return nil }
        return known[MagicCore.clampedSelection(selection, count: known.count)]
    }

    func carriedSpellTomes() -> [(item: FormID, spell: FormID)] {
        carriedItems { items, item in items.teachesSpell(item).map { (item: item, spell: $0) } }
    }

    private func itemName(_ item: FormID) -> String {
        world?.itemName(item) ?? item.description
    }

    private func castingUnavailable() -> String {
        castingActionText = MagicCore.castingUnavailableText
        return castingActionText
    }

    private func readout(_ spell: ResolvedSpell, book: SpellbookState) -> KnownSpellReadout {
        let hands = book.hands(of: spell.key)
        return KnownSpellReadout(
            name: spell.displayName,
            typeName: spell.spellType.description,
            castingName: (spell.data?.castingType).map(String.init(describing:)) ?? "unknown",
            deliveryName: (spell.data?.delivery).map(String.init(describing:)) ?? "unknown",
            cost: spell.cost.cost,
            chargeTime: spell.data?.chargeTime ?? 0,
            readiedHands: SpellHand.allCases
                .filter { hands.contains($0.slots) }
                .map(\.describedName)
        )
    }
}
