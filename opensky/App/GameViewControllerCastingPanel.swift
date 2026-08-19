// The `World > Combat & Physics > Spellcasting` panel's provider conformance
// (issue #470, roadmap item 19.7): the panel actions and the one snapshot the
// readout is a pure function of.
//
// Split from `GameViewControllerCasting.swift` so both stay under the
// strict-lint length cap, and along the same seam every other bridge splits on:
// that file wires the runtime and drives the frame, this one answers the panel.
//
// Every action reports a sentence the panel shows verbatim, because a refusal
// with a reason is the whole point of the surface — "not enough magicka: 73
// needed, 40 available" is what makes an unspent cast legible rather than a
// button that did nothing.

import AppKit

extension GameViewController: CastingControlProviding {
    var castingControlSnapshot: CastingControlSnapshot {
        guard let runtime = casting.runtime else { return .unavailable }
        let known = playerKnownSpells()
        let selected = selectedKnownSpell()
        let book = runtime.spellbook.state(of: .player)
        return CastingControlSnapshot(
            isAvailable: true,
            knownSpells: known.map { readout($0, book: book) },
            selectedSpellName: selected?.displayName,
            leftPhase: runtime.phase(of: .left),
            rightPhase: runtime.phase(of: .right),
            magicka: runtime.values.current(of: .player).magicka,
            maximumMagicka: runtime.values.maximums(of: .player).magicka,
            carriedTomeNames: carriedSpellTomes().map { name(of: $0.item) },
            readBookCount: book.readBooks.count,
            castCount: runtime.tally.castCount,
            concentrationSeconds: runtime.tally.concentrationSeconds,
            failureCount: runtime.tally.failureCount,
            failureLines: runtime.tally.failureLines,
            unheldAbilityEntries: runtime.tally.unheldAbilityEntries,
            projectileCount: runtime.tally.projectileCount,
            deliveryLines: runtime.tally.deliveryLines,
            lastHitTargets: magicEffects.lastHit?.targetCount ?? 0,
            lastHitAdjustments: magicEffects.lastHit?.adjustments.map(\.line) ?? [],
            conditionLines: magicConditionLines(),
            lastActionText: casting.lastActionText
        )
    }

    @discardableResult
    func grantPlayerStartSpells() -> String {
        guard let runtime = casting.runtime else { return unavailableCastingText() }
        let granted = runtime.spellbook.grantStartSpells(
            to: .player,
            additional: playerRacialSpells()
        )
        let held = runtime.applyAbilities(on: .player)
        casting.lastActionText = granted == 0
            ? "Every start spell was already known."
            : "Learned \(granted) start spell(s); \(held) ability effect(s) now running."
        return casting.lastActionText
    }

    @discardableResult
    func readFirstCarriedSpellTome() -> String {
        guard let runtime = casting.runtime else { return unavailableCastingText() }
        guard let tome = carriedSpellTomes().first else {
            casting.lastActionText = "The player carries no spell tome."
            return casting.lastActionText
        }
        let plugin = magicEffects.pluginName
        let bookKey = runtime.spellbook.spells.resolvedID(tome.item, fromPlugin: plugin)
            .map(ReferenceKey.init(resolved:))
        let spellKey = runtime.spellbook.spells.resolvedID(tome.spell, fromPlugin: plugin)
            .map(ReferenceKey.init(resolved:))
        guard let bookKey else {
            casting.lastActionText = "Could not resolve \(name(of: tome.item)) in \(plugin)."
            return casting.lastActionText
        }
        let reading = runtime.spellbook.read(book: bookKey, teaching: spellKey, on: .player)
        casting.lastActionText = Self.readingText(reading, book: name(of: tome.item))
        return casting.lastActionText
    }

    @discardableResult
    func selectNextKnownSpell() -> String {
        let known = playerKnownSpells()
        guard !known.isEmpty else {
            casting.lastActionText = "The player knows no spells to select."
            return casting.lastActionText
        }
        casting.selection = (min(max(0, casting.selection), known.count - 1) + 1) % known.count
        casting.lastActionText = "Selected \(known[casting.selection].displayName)."
        return casting.lastActionText
    }

    @discardableResult
    func readySelectedSpell(in hand: SpellHand) -> String {
        guard let runtime = casting.runtime else { return unavailableCastingText() }
        guard let spell = selectedKnownSpell() else {
            casting.lastActionText = "No spell selected to ready."
            return casting.lastActionText
        }
        do {
            let change = try runtime.spellbook.equip(
                spell.key,
                in: hand,
                on: .player,
                inventory: worldItems.runtime?.player
            )
            casting.lastActionText = Self.readyText(change, name: spell.displayName) {
                self.name(of: $0)
            }
        } catch {
            casting.lastActionText = "Could not ready \(spell.displayName): "
                + String(describing: error)
        }
        return casting.lastActionText
    }

    @discardableResult
    func castReadiedSpell(in hand: SpellHand) -> String {
        guard let runtime = casting.runtime else { return unavailableCastingText() }
        let outcome = runtime.begin(hand, on: .player)
        if let failure = outcome.failure {
            casting.lastActionText = "Cast refused: \(failure.describedReason)"
            return casting.lastActionText
        }
        // Fast-forward the charge, then the maintenance floor, so one button
        // press is one whole cast. The held-button path in `advanceCasting`
        // reaches the same states over real frames.
        runtime.advance(
            delta: runtime.state(of: hand).phase == .charging ? chargeStep : 0,
            on: .player
        )
        if runtime.phase(of: hand) == .concentrating {
            runtime.advance(delta: 1, on: .player)
        }
        casting.lastActionText = Self.castText(runtime.release(hand, on: .player))
        return casting.lastActionText
    }

    // MARK: - Private

    /// Seconds one panel cast fast-forwards the charge by. Longer than any
    /// vanilla SPIT charge time, so a single press always reaches the release
    /// window; the loop clamps at the spell's own charge time anyway.
    private var chargeStep: Float {
        4
    }

    /// The `SPLO` list of the race the player's baseline is derived from, as
    /// runtime keys.
    ///
    /// Empty until character generation names a race (M18), which is also when
    /// the actor-value baseline stops falling back — the two read the same
    /// `playerRace`, so a session cannot have one race's attributes and another
    /// race's powers.
    private func playerRacialSpells() -> [ReferenceKey] {
        guard
            let runtime = casting.runtime,
            let baselines = actorValues.runtime?.baselines,
            let raceID = baselines.playerRace,
            let race = baselines.resolver?.races[raceID.rawValue]
        else { return [] }
        return runtime.spellbook.resolve(race.spells, fromPlugin: magicEffects.pluginName)
    }

    private func unavailableCastingText() -> String {
        casting.lastActionText = "Spellcasting unavailable: no game data loaded."
        return casting.lastActionText
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

    private static func readingText(_ reading: SpellTomeReading, book: String) -> String {
        if reading.alreadyRead {
            return "\(book) was already read."
        }
        return reading.taught
            ? "Read \(book) and learned the spell it teaches."
            : "Read \(book); it taught nothing new."
    }

    private static func readyText(
        _ change: SpellEquipChange,
        name: String,
        itemName: (FormID) -> String
    ) -> String {
        let hands = SpellHand.allCases
            .filter { change.hands.contains($0.slots) }
            .map(\.describedName)
            .joined(separator: " and ")
        var text = "Readied \(name) in the \(hands)."
        if !change.unequippedItems.isEmpty {
            text += " Unequipped \(change.unequippedItems.map(itemName).joined(separator: ", "))."
        }
        return text
    }

    private static func castText(_ outcome: SpellCastOutcome) -> String {
        switch outcome {
        case let .cast(result):
            String(
                format: "Cast: %.0f magicka spent, %d effect entries, %d now running.",
                result.magickaSpent, result.entryCount, result.storedCount
            )
        case let .released(_, held, spent):
            String(
                format: "Maintained for %.1fs, %.0f magicka spent.", held, spent
            )
        case let .failed(reason):
            "Cast refused: \(reason.describedReason)"
        case .charging, .ready, .concentrating:
            "Cast is still running."
        case .ignored:
            "Nothing to cast in that hand."
        }
    }
}
