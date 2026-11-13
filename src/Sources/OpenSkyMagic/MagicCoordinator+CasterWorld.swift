// The world the caster runtime casts in: skill use, effects, projectiles and aim.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyProgressionInterface
import OpenSkyWorldState
import simd

extension MagicCoordinator.CasterBridge {
    var castingGameDay: Int32 {
        MagicCore.gameDay(coordinator.world.gameDaysPassed)
    }

    func castsFromFlyingMount(key: ReferenceKey) -> Bool {
        coordinator.world.isOnFlyingMount(key)
    }

    @discardableResult
    func reportSkillUse(_ use: SkillUseEvent) -> Float {
        coordinator.world.reportSkillUse(use)
    }

    func applyCastEffects(
        _ entries: [MagicItemEffect],
        origin: (plugin: String, source: ActiveEffectSource),
        caster: ReferenceKey,
        on target: ActorValueHolder
    ) -> Int {
        let (pluginName, source) = origin
        let scaled = source.kind == .spell
            ? coordinator.perkEffects.perkScaled(
                entries,
                of: source.record,
                caster: caster,
                on: target.key
            )
            : entries
        let isDualCast = coordinator.caster?.isApplyingDualCast == true
        let stored = coordinator.withEffects { runtime in
            runtime.application.isDualCast = isDualCast
            defer { runtime.application = MagicApplicationContext() }
            return runtime.apply(
                scaled, fromPlugin: pluginName, source: source, caster: caster, on: target
            )
        }
        return stored?.count ?? 0
    }

    @discardableResult
    func fireSpellProjectile(_ payload: SpellPayload) -> Bool {
        coordinator.world.fireSpellProjectile(payload)
    }

    func aimedSpellTarget(within range: Float, for caster: ReferenceKey) -> SpellAim {
        coordinator.world.aimedSpellTarget(within: range, for: caster)
    }

    /// Casting breaks the caster's invisibility. The wiki says only the player's
    /// casts count as a story event.
    func spellWasCast(_ spell: ReferenceKey, by caster: ReferenceKey) {
        coordinator.world.noteSpellCast(spell, by: caster)
        coordinator.archetypeActions.breakInvisibility(of: caster)
        guard caster == .player, let storyEvents = coordinator.storyEvents else { return }
        storyEvents.reportStoryEvent(.castMagic(
            caster: caster,
            target: aimedSpellTarget(within: 0, for: caster).target,
            location: nil,
            spell: StoryEventData.form(of: spell)
        ))
    }

    func spellHitCandidates() -> [MeleeTarget] {
        coordinator.world.spellHitCandidates()
    }

    /// A projectile hit and a direct cast take this one path, so the effects
    /// readout's tally counts both.
    @discardableResult
    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        let holders = residentHolders(of: hit.targets)
        guard
            let report = coordinator.withEffects({ runtime in
                runtime.application.isDualCast = hit.payload.isDualCast
                defer { runtime.application = MagicApplicationContext() }
                return SpellHitApplication
                    .apply(
                        hit, holders: holders, using: &runtime,
                        defences: coordinator.wardShields.spellHitDefences()
                    ) { entries, target in
                        coordinator.perkEffects.perkScaled(
                            entries, of: hit.payload.spell, caster: hit.payload.caster, on: target
                        )
                    }
            })
        else { return .none }
        coordinator.wardShields.breakWards(report.brokenWards)
        if hit.payload.caster == .player {
            noteRefusals(report.refusals, of: hit.payload, holders: holders)
        }
        for wardHit in report.wardHits {
            coordinator.pendingCommands.append(
                .wardHit(wardHit, caster: hit.payload.caster, spell: hit.payload.spell)
            )
        }
        if !hit.targets.isEmpty, let store = coordinator.effects?.effects {
            coordinator.pendingCommands.append(
                .spellHit(SpellHitEvent(hit: hit, links: store.hitEffectLinks(of: hit.payload)))
            )
        }
        return report
    }

    /// The player's spell refused by a named target: the game's notice for each.
    private func noteRefusals(
        _ refusals: [SpellTargetRefusal], of payload: SpellPayload,
        holders: [ReferenceKey: ActorValueHolder]
    ) {
        let delivery = coordinator.caster?.spellbook.spells.spell(key: payload.spell)?.data?
            .delivery
        for refusal in refusals where refusal.target != .player {
            guard
                let holder = holders[refusal.target],
                let name = coordinator.world.displayName(of: holder),
                let text = MagicHitNoticeText.notice(
                    for: refusal, names: (name, payload.name),
                    isTouch: delivery == .touch, texts: coordinator.texts.hitNotices
                )
            else { continue }
            coordinator.pendingCommands.append(.notice(text))
        }
    }

    /// The holder of each target still resident. A target that left is absent.
    func residentHolders(of targets: [SpellHitTarget]) -> [ReferenceKey: ActorValueHolder] {
        var holders: [ReferenceKey: ActorValueHolder] = [:]
        for target in targets {
            holders[target.key] = coordinator.world.actorValueHolder(for: target.key)
        }
        return holders
    }

    /// Each call below has a protocol default, so without it the default answers.
    func spellLanded(_ payload: SpellPayload, at point: SIMD3<Float>) {
        coordinator.worldArchetypeActions.spellLanded(payload, at: point)
    }

    func deliverToLocation(
        _ payload: SpellPayload, spell: ResolvedSpell, caster: ActorValueHolder
    ) -> Int {
        coordinator.runePlacement.deliverToLocation(payload, spell: spell, caster: caster)
    }
}
