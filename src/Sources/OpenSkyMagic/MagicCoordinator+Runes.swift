// Target-location casts and runes: the cast lands where the caster aims, or waits there
// as a rune until a hostile actor comes near. The rules live in `RuneCore`.
// See docs/engine/spell-delivery.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface

extension MagicCoordinator.RunePlacement {
    func deliverToLocation(
        _ payload: SpellPayload, spell: ResolvedSpell, caster: ActorValueHolder
    ) -> Int {
        let reach = targetLocationReach(of: spell, caster: caster.key)
        var aim = coordinator.world.aimedSpellTarget(within: reach, for: caster.key)
        if
            spell.snapsToNavmesh,
            let snapped = coordinator.world.navmeshPoint(
                near: aim.position, within: RuneCore.navmeshSnapRadius
            )
        {
            aim = SpellAim(target: aim.target, position: snapped, candidates: aim.candidates)
        }
        return land(payload, at: aim)
    }

    /// `payload` at `aim`: a rune waits there, anything else applies now.
    @discardableResult
    func land(_ payload: SpellPayload, at aim: SpellAim) -> Int {
        if isRune(payload) {
            let rune = PlacedRune(
                payload: payload,
                position: aim.position,
                proximity: RuneCore.proximity(
                    coordinator.world.projectileProximity(of: payload),
                    outdoors: coordinator.world.isOutdoors,
                    settings: coordinator.rules.runes
                )
            )
            coordinator.runeState.runes = RuneCore.placing(
                rune,
                in: coordinator.runeState.runes,
                settings: coordinator.rules.runes
            )
            return 0
        }
        if summons(payload) {
            // The effect runs on the caster; the creature appears at the aim point.
            coordinator.summonPoints[payload.caster] = aim.position
            return coordinator.casterBridge.applySpellHit(SpellHit(
                payload: payload, targets: [SpellHitTarget(key: payload.caster)],
                impact: aim.position
            )).storedCount
        }
        let targets = SpellHitTargeting.targets(
            of: payload, landing: (aim.position, aim.target), candidates: aim.candidates,
            excluding: payload.caster
        )
        guard !targets.isEmpty else { return 0 }
        return coordinator.casterBridge.applySpellHit(SpellHit(
            payload: payload,
            targets: targets,
            impact: aim.position
        ))
        .storedCount
    }

    /// Sets off every rune a hostile actor came near, oldest first.
    func advanceRunes(delta: Float) {
        guard !coordinator.runeState.runes.isEmpty else { return }
        let step = delta.isFinite ? max(delta, 0) : 0
        var triggers: [ReferenceKey: [MeleeTarget]] = [:]
        var waiting: [PlacedRune] = []
        var fired: [(rune: PlacedRune, struck: ReferenceKey)] = []
        let casterMay = coordinator.rules.runes.casterCanTrigger != 0
        for var rune in coordinator.runeState.runes {
            rune.age += step
            let caster = rune.payload.caster
            let near = triggers[caster] ?? coordinator.world.runeTriggers(for: caster)
                +
                (casterMay ? coordinator.world.spellHitCandidates()
                    .filter { $0.key == caster } : [])
            triggers[caster] = near
            for target in RuneCore.nearby(rune, among: near, settings: coordinator.rules.runes)
                where !rune.fuse.isBurning
            {
                rune.fuse.notice(target.key, playerRoll: playerSetsOffMine)
            }
            if rune.fuse.burn(step), let struck = rune.fuse.trigger {
                fired.append((rune: rune, struck: struck))
            } else {
                waiting.append(rune)
            }
        }
        coordinator.runeState.runes = waiting
        for (rune, struck) in fired {
            detonate(rune, struck: struck)
        }
    }

    /// Every rune waiting on the ground, for the renderer.
    var markers: [RuneMarker] {
        coordinator.runeState.runes.map {
            RuneMarker(
                position: $0.position,
                projectile: $0.payload.projectile,
                isLit: $0.fuse.isLit
            )
        }
    }

    /// The readout line: placed runes against the player's limit, how many burn a fuse,
    /// and how many went off.
    var runeText: String {
        let state = coordinator.runeState
        let mine = state.runes.count { $0.payload.caster == .player }
        let burning = state.runes.count(where: \.fuse.isBurning)
        let limit = coordinator.rules.runes.maximumPlayerRunes
        return "Runes: \(mine) of \(limit) placed by the player, "
            + "\(state.runes.count - mine) by others, \(burning) burning, "
            + "\(state.detonatedRunes) went off"
    }

    /// The player's roll against Calculate Mine Explode Chance, from 100.
    private func playerSetsOffMine() -> Bool {
        let chance = coordinator.world.perkModified(
            100, at: .calculateMineExplodeChance, on: .player,
            subjects: PerkEvaluationSubjects(owner: .player), seams: ConditionContext()
        )
        return MineFuse.playerPasses(chance: chance, roll: coordinator.mineRoll())
    }

    /// The struck actor takes every entry; others inside an entry's area take theirs.
    private func detonate(_ rune: PlacedRune, struck: ReferenceKey) {
        let targets = SpellHitTargeting.targets(
            of: rune.payload, landing: (rune.position, struck),
            candidates: coordinator.world.spellHitCandidates(), excluding: rune.payload.caster
        )
        if !targets.isEmpty {
            coordinator.casterBridge.applySpellHit(SpellHit(
                payload: rune.payload,
                targets: targets,
                impact: rune.position
            ))
        }
        coordinator.runeState.detonatedRunes += 1
        coordinator.pendingCommands.append(.detonateRune(rune.payload, at: rune.position))
    }

    /// `SPIT` range through entry point 88, as Rune Master's "five times farther".
    private func targetLocationReach(of spell: ResolvedSpell, caster: ReferenceKey) -> Float {
        let range = spell.data?.range ?? 0
        guard let spells = coordinator.caster?.spellbook.spells
        else { return RuneCore.reach(range: range) }
        var seams = ConditionContext()
        seams[resolution: SpellEvaluationResolution.self] = SpellEvaluationResolution(spell: spell)
        let subjects = PerkEvaluationSubjects(owner: caster)
            .binding(.spell, to: spells.conditionSubject(of: spell))
        return RuneCore.reach(range: coordinator.world.perkModified(
            range, at: .modSpellRangeTargetLoc, on: caster, subjects: subjects, seams: seams
        ))
    }

    private func summons(_ payload: SpellPayload) -> Bool {
        guard let store = coordinator.effects?.effects else { return false }
        return payload.entries.contains { entry in
            store.resolve(entry.effect, fromPlugin: payload.sourcePlugin)?.effect.data?
                .archetype == .summonCreature
        }
    }

    private func isRune(_ payload: SpellPayload) -> Bool {
        guard
            let store = coordinator.effects?.effects,
            let keyword = coordinator.world.keyword(editorID: RuneCore.keyword)
        else { return false }
        return RuneCore.isRune(payload, store: store, keyword: keyword)
    }
}
