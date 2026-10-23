// The Magic Effects and Spellcasting readouts, read off the runtimes
// `MagicCoordinator` owns. Every action returns the sentence the readout shows.

import Foundation
import OpenSkyActorsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyWorldState

extension MagicCoordinator {
    public var magicEffectControlSnapshot: MagicEffectControlSnapshot {
        guard let runtime = effects else { return .unavailable }
        let tally = runtime.tally
        let nearest = world.nearestActorValueHolder()
        var snapshot = MagicEffectControlSnapshot(
            isAvailable: true,
            playerEffects: runtime.active(on: .player).map { readout(of: $0, runtime: runtime) },
            nearestActorName: nearest.map { world.actorName($0) },
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
            lastActionText: lastEffectAction.text
        )
        snapshot.worldEffectLines = holdLines + lightLines
        snapshot.playerInfluence = runtime.influence(on: .player)
        snapshot.nearestActorInfluence = nearest.map { runtime.influence(on: $0) } ?? .none
        return snapshot
    }

    @discardableResult
    public func consumeFirstCarriedMagicItem() -> MagicEffectActionOutcome {
        guard effects != nil else { return recordEffect(.unavailable) }
        let item = carriedItems { items, item in items.magicItemUse(item) == nil ? nil : item }
            .first
        guard let item else { return recordEffect(.nothingToConsume) }
        return consumeMagicItem(item)
    }

    @discardableResult
    public func dispelPlayerMagicEffects() -> MagicEffectActionOutcome {
        guard let removed = withEffects({ $0.dispelAll(on: .player) }) else {
            return recordEffect(.unavailable)
        }
        return recordEffect(.dispelled(removed: removed))
    }

    private func readout(
        of effect: ActiveEffect,
        runtime: ActiveEffectRuntime
    ) -> ActiveEffectReadout {
        var readout = ActiveEffectReadout(
            name: effectName(effect.effect, runtime: runtime),
            sourceName: sourceName(effect.source.kind),
            mode: effect.mode,
            isDetrimental: effect.isDetrimental,
            magnitude: effect.values.first?.magnitude ?? 0,
            duration: effect.duration,
            remaining: effect.remaining,
            valueNames: effect.values
                .filter { ActorValueIdentity.isVanilla(index: $0.index) }
                .map { ActorValueIdentity.description(of: $0.index) },
            archetype: archetypeText(of: effect, runtime: runtime)
        )
        if effect.duration > 0 {
            readout.timeLeftText = magicTexts.timeLeft(effect.remaining)
        }
        return readout
    }

    /// The archetype and what it does, such as "light: carries a light".
    private func archetypeText(of effect: ActiveEffect, runtime: ActiveEffectRuntime) -> String {
        guard let archetype = runtime.effects.effect(key: effect.effect)?.effect.data?.archetype
        else { return "unknown" }
        guard let rule = MagicArchetypeRule.rule(for: archetype) else {
            return archetype.description
        }
        return "\(archetype.description): \(rule.summary)"
    }

    /// One line per light the Light archetype placed.
    private var lightLines: [String] {
        magicLights.map { light in
            switch light.anchor {
            case let .actor(key): "light \(light.light) on \(key)"
            case let .point(point):
                String(
                    format: "light %@ at (%.0f, %.0f, %.0f), %.0fs left",
                    "\(light.light)", point.x, point.y, point.z, light.remaining ?? 0
                )
            }
        }
    }

    private func sourceName(_ kind: ActiveEffectSourceKind) -> String {
        let setting: String? = switch kind {
        case .potion: "sMagicTypePotion"
        case .ingredient: "sIngredient"
        case .spell: "sMagicTypeSpell"
        case .enchantment: "sMagicTypeEnchantment"
        case .ability: "sMagicTypeAbility"
        case .perk: nil
        }
        return setting.map { magicTexts.word($0, or: kind.describedName) } ?? kind.describedName
    }

    /// Falls back to the key, so a line names something even when the record
    /// left the load order.
    private func effectName(_ key: ReferenceKey, runtime: ActiveEffectRuntime) -> String {
        guard case let .plugin(name, objectID) = key else { return key.description }
        let resolved = ResolvedFormID(plugin: name, objectID: objectID)
        return runtime.effects.effect(resolved)?.displayName ?? key.description
    }
}

extension MagicCoordinator {
    public var castingControlSnapshot: CastingControlSnapshot {
        guard let caster else { return .unavailable }
        let book = caster.spellbook.state(of: .player)
        let tally = caster.tally
        var snapshot = CastingControlSnapshot(
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
            abilityEffectCount: effects?.active(on: .player)
                .filter { $0.source.kind == .ability }.count ?? 0,
            projectileCount: tally.projectileCount,
            deliveryLines: tally.deliveryLines,
            lastHitTargets: lastHit?.targetCount ?? 0,
            lastHitAdjustments: (lastHit?.defenceLines ?? [])
                + (lastHit?.adjustments.map(\.line) ?? []),
            conditionLines: magicConditionLines(),
            lastActionText: lastCastingAction.text
        )
        snapshot.soulLines = soulLines()
        snapshot.runeText = runeText
        snapshot.commandedText = commandedText
        snapshot.castingCueText = castingCueText
        return snapshot
    }

    @discardableResult
    func readSpellTome(_ item: FormID, spell: FormID) -> CastingActionOutcome {
        guard let caster else { return recordCasting(.unavailable) }
        let spells = caster.spellbook.spells
        let bookKey = spells.resolvedID(item, fromPlugin: pluginName)
            .map(ReferenceKey.init(resolved:))
        let spellKey = spells.resolvedID(spell, fromPlugin: pluginName)
            .map(ReferenceKey.init(resolved:))
        guard let bookKey else {
            return recordCasting(.unresolvedTome(book: itemName(item), plugin: pluginName))
        }
        let reading = caster.spellbook.read(book: bookKey, teaching: spellKey, on: .player)
        return recordCasting(.readTome(reading, book: itemName(item)))
    }

    @discardableResult
    public func selectNextKnownSpell() -> CastingActionOutcome {
        let known = playerKnownSpells()
        guard !known.isEmpty else { return recordCasting(.noSpellsKnown) }
        selection = MagicCore.nextSelection(after: selection, count: known.count)
        return recordCasting(.selected(spell: known[selection].displayName))
    }

    @discardableResult
    public func readySelectedSpell(in hand: SpellHand) -> CastingActionOutcome {
        guard let caster else { return recordCasting(.unavailable) }
        guard let spell = selectedKnownSpell() else { return recordCasting(.noSpellSelected) }
        do {
            let change = try caster.spellbook.equip(
                spell.key, in: hand, on: .player, inventory: world.inventory == nil ? nil : .player
            )
            return recordCasting(.readied(
                change, spell: spell.displayName, unequipped: change.unequippedItems.map(itemName)
            ))
        } catch {
            return recordCasting(.readyFailed(
                spell: spell.displayName, reason: String(describing: error)
            ))
        }
    }

    /// Fast-forwards the charge, then the maintenance floor, so one press is
    /// one whole cast. Held buttons reach the same states over real frames.
    @discardableResult
    public func castReadiedSpell(in hand: SpellHand) -> CastingActionOutcome {
        guard let caster else { return recordCasting(.unavailable) }
        let outcome = caster.begin(hand, on: .player)
        if let failure = outcome.failure {
            return recordCasting(.cast(.failed(failure)))
        }
        let charge = caster.state(of: hand).phase == .charging ? MagicCore.panelChargeStep : 0
        caster.advance(delta: charge, on: .player)
        if caster.phase(of: hand) == .concentrating {
            caster.advance(delta: 1, on: .player)
        }
        return recordCasting(.cast(caster.release(hand, on: .player)))
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
        world.itemName(item)
    }

    private func readout(_ spell: ResolvedSpell, book: SpellbookState) -> KnownSpellReadout {
        let hands = book.hands(of: spell.key)
        return KnownSpellReadout(
            name: spell.displayName,
            typeName: magicTexts.name(of: spell.spellType),
            castingName: (spell.data?.castingType).map(magicTexts.name(of:)) ?? "unknown",
            deliveryName: (spell.data?.delivery).map(magicTexts.name(of:)) ?? "unknown",
            cost: spell.cost.cost,
            chargeTime: spell.data?.chargeTime ?? 0,
            readiedHands: SpellHand.allCases
                .filter { hands.contains($0.slots) }
                .map(\.describedName),
            schoolName: spell.magicSkill.flatMap(magicTexts.school(of:)).map { school in
                spell.minimumSkillLevel.map { "\(magicTexts.level(minimumSkill: $0)) \(school)" }
                    ?? school
            }
        )
    }
}
