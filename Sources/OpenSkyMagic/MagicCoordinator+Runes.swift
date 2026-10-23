// Target-location casts and runes: the cast lands where the caster aims, or waits there
// as a rune until a hostile actor comes near. The rules live in `RuneCore`.
// See docs/engine/spell-delivery.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface

extension MagicCoordinator {
    public func deliverToLocation(
        _ payload: SpellPayload, spell: ResolvedSpell, caster: ActorValueHolder
    ) -> Int {
        let reach = targetLocationReach(of: spell, caster: caster.key)
        return land(payload, at: world.aimedSpellTarget(within: reach, for: caster.key))
    }

    /// `payload` at `aim`: a rune waits there, anything else applies now.
    @discardableResult
    func land(_ payload: SpellPayload, at aim: SpellAim) -> Int {
        if isRune(payload) {
            let proximity = world.projectileProximity(of: payload)
            let rune = PlacedRune(
                payload: payload,
                position: aim.position,
                proximity: proximity > 0 ? proximity : RuneCore.defaultProximity
            )
            runes = RuneCore.placing(rune, in: runes, settings: runeSettings)
            return 0
        }
        if summons(payload) {
            // The effect runs on the caster; the creature appears at the aim point.
            summonPoints[payload.caster] = aim.position
            return applySpellHit(SpellHit(
                payload: payload, targets: [SpellHitTarget(key: payload.caster)],
                impact: aim.position
            )).storedCount
        }
        let targets = SpellHitTargeting.targets(
            of: payload, at: aim.position, struck: aim.target, candidates: aim.candidates,
            excluding: payload.caster
        )
        guard !targets.isEmpty else { return 0 }
        return applySpellHit(SpellHit(payload: payload, targets: targets, impact: aim.position))
            .storedCount
    }

    /// Sets off every rune a hostile actor came near, oldest first.
    func advanceRunes() {
        guard !runes.isEmpty else { return }
        var triggers: [ReferenceKey: [MeleeTarget]] = [:]
        var waiting: [PlacedRune] = []
        var fired: [(rune: PlacedRune, struck: ReferenceKey)] = []
        for rune in runes {
            let caster = rune.payload.caster
            let near = triggers[caster] ?? world.runeTriggers(for: caster)
            triggers[caster] = near
            if let trigger = RuneCore.trigger(of: rune, among: near) {
                fired.append((rune: rune, struck: trigger.key))
            } else {
                waiting.append(rune)
            }
        }
        runes = waiting
        for (rune, struck) in fired {
            detonate(rune, struck: struck)
        }
    }

    /// The readout line: placed runes against the player's limit, and how many went off.
    var runeText: String {
        let mine = runes.count { $0.payload.caster == .player }
        return "Runes: \(mine) of \(runeSettings.maximumPlayerRunes) placed by the player, "
            + "\(runes.count - mine) by others, \(detonatedRunes) went off"
    }

    /// The struck actor takes every entry; others inside an entry's area take theirs.
    private func detonate(_ rune: PlacedRune, struck: ReferenceKey) {
        let targets = SpellHitTargeting.targets(
            of: rune.payload, at: rune.position, struck: struck,
            candidates: world.spellHitCandidates(), excluding: rune.payload.caster
        )
        if !targets.isEmpty {
            applySpellHit(SpellHit(payload: rune.payload, targets: targets, impact: rune.position))
        }
        detonatedRunes += 1
        pendingCommands.append(.detonateRune(rune.payload, at: rune.position))
    }

    /// `SPIT` range through entry point 88, as Rune Master's "five times farther".
    private func targetLocationReach(of spell: ResolvedSpell, caster: ReferenceKey) -> Float {
        let range = spell.data?.range ?? 0
        guard let spells = self.caster?.spellbook.spells
        else { return RuneCore.reach(range: range) }
        var seams = ConditionContext()
        seams.spellEvaluation = SpellEvaluationResolution(spell: spell)
        let subjects = PerkEvaluationSubjects(owner: caster)
            .binding(.spell, to: spells.conditionSubject(of: spell))
        return RuneCore.reach(range: world.perkModified(
            range, at: .modSpellRangeTargetLoc, on: caster, subjects: subjects, seams: seams
        ))
    }

    private func summons(_ payload: SpellPayload) -> Bool {
        guard let store = effects?.effects else { return false }
        return payload.entries.contains { entry in
            store.resolve(entry.effect, fromPlugin: payload.sourcePlugin)?.effect.data?
                .archetype == .summonCreature
        }
    }

    private func isRune(_ payload: SpellPayload) -> Bool {
        guard
            let store = effects?.effects,
            let keyword = world.keyword(editorID: RuneCore.keyword)
        else { return false }
        return RuneCore.isRune(payload, store: store, keyword: keyword)
    }
}
