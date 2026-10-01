// World > Runtime State live bridge, conditions half. The selectable lists are
// the MUST tracks with at least one CTDA condition. Globals, clock, and quest
// state are live; subject and target are the crosshair reference. The random
// stream starts from `ConditionRandom`'s default seed on every evaluation, so
// an unchanged world gives the same answer.

import AppKit
import OpenSkyActors
import OpenSkyActorsInterface
import OpenSkyAudio
import OpenSkyCombat
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import OpenSkyScripting
import OpenSkyWorld
import OpenSkyWorldState

extension GameViewController {
    var runtimeStateConditionSources: [String] {
        runtimeStateConditionSourceFormIDs().keys.sorted()
    }

    func evaluateConditions(source: String) -> RuntimeStateConditionReport {
        guard let musicStore = runtimeStateMusicStore else {
            return .unavailable(
                source: source,
                message: "No music records are loaded, so no condition list can be evaluated."
            )
        }
        guard
            let formID = runtimeStateConditionSourceFormIDs()[source],
            let track = musicStore.musicTrack(formID)
        else {
            return .unavailable(source: source, message: "No condition list named \(source).")
        }
        var tally = runtimeState.conditionTally
        let report = RuntimeStateConditionRunner.report(
            source: source,
            conditions: track.conditions,
            context: runtimeStateConditionContext(),
            tally: &tally
        )
        runtimeState.conditionTally = tally
        return report
    }

    /// Live evaluation context: current globals, quest state (`QuestRuntime`),
    /// clock, and the crosshair reference as subject and target. `aliasQuest` stays
    /// nil because MUST conditions belong to no quest. The reference index holds the
    /// crosshair entry plus every resident actor, so a combat-target run-on resolves.
    /// Dialogue selection uses this context too, and overrides `subject`, `target`,
    /// and `aliasQuest` per response.
    func runtimeStateConditionContext() -> ConditionContext {
        let entry = runtimeStateEntry(for: .currentTarget)
        return ConditionContext(
            globals: runtimeStateGlobalResolution(),
            quests: papyrusBridge?.questRuntime?.resolution() ?? .empty,
            aliases: papyrusBridge?.questRuntime?.aliasResolution() ?? .empty,
            actors: runtimeStateActorResolution(),
            detection: perceptionResolution(),
            magic: magicConditionResolution(),
            crime: crimeConditionResolution(),
            factions: factionConditionResolution(),
            clock: renderer?.gameClock,
            references: runtimeStateConditionReferences(crosshair: entry),
            subject: entry?.key,
            target: entry?.key
        )
    }

    /// The crosshair's reference and every resident actor, deduplicated by the
    /// index itself.
    private func runtimeStateConditionReferences(
        crosshair: RuntimeReferenceEntry?
    ) -> RuntimeReferenceIndex {
        var entries = crosshair.map { [$0] } ?? []
        for observation in combatActors() {
            guard
                let entry = streamer?.referenceEntry(key: observation.key),
                entry.key != crosshair?.key
            else { continue }
            entries.append(entry)
        }
        return RuntimeReferenceIndex(entries: entries)
    }

    /// The actor condition functions' seam: every resident actor plus the player,
    /// with the fight the combat loop derived filled in both directions.
    func runtimeStateActorResolution() -> ActorStateResolution {
        guard let values = actorValues.runtime else { return .empty }
        var states: [ReferenceKey: ActorConditionState] = [
            .player: actorConditionState(holder: .player, values: values)
        ]
        for observation in combatActors() {
            guard let holder = runtimeStateActorHolder(for: observation.key) else {
                continue
            }
            states[observation.key] = actorConditionState(
                holder: holder, values: values, isDead: observation.isDead
            )
        }
        return ActorStateResolution.fight(
            states: states,
            playerKey: .player,
            playerTarget: combat.loop?.state.target
        )
    }

    /// One actor's values, death, combat activity, and draw state as a condition reads
    /// them. Only the player has a graph tracking a draw state, so every other
    /// actor carries nil and `IsWeaponOut` reports the gap.
    private func actorConditionState(
        holder: ActorValueHolder,
        values: ActorValueRuntime,
        isDead: Bool = false
    ) -> ActorConditionState {
        let baseline = values.baseline(of: holder)
        return ActorConditionState(
            current: values.current(of: holder),
            maximums: values.maximums(of: holder),
            isDead: isDead,
            combatActivity: combat.loop?.activity(of: holder.key) ?? .notFighting,
            weaponDrawState: holder.key == .player
                ? combat.melee?.state.drawState
                : nil,
            general: values.resolvedEntries(of: holder),
            generalBaseline: baseline.basesByIndex,
            level: baseline.level
        )
    }

    /// The actor-value holder behind a resident actor, or nil when nothing
    /// resident answers to the key.
    private func runtimeStateActorHolder(for key: ReferenceKey) -> ActorValueHolder? {
        guard
            let streamer,
            let actor = streamer.referenceEntry(key: key)?.placedActor
        else { return nil }
        return ActorValueHolder(
            key: key,
            subject: .actor(base: actor.base),
            cell: streamer.cellLocation(of: key)
        )
    }

    /// Selectable list name to the MUST record it came from. A track without an
    /// editor ID is named by its FormID so it is still addressable, and a name
    /// already taken keeps the first record — the map is only a way to point at
    /// a record, and silently retargeting a name would be worse than omitting
    /// the duplicate.
    private func runtimeStateConditionSourceFormIDs() -> [String: FormID] {
        if let cached = runtimeState.conditionSourceFormIDs {
            return cached
        }
        let tracks = (runtimeStateMusicStore?.musicTracks.values).map {
            $0.sorted { $0.formID.rawValue < $1.formID.rawValue }
        } ?? []
        var sources: [String: FormID] = [:]
        for track in tracks where !track.conditions.isEmpty {
            let name = track.editorID ?? track.formID.description
            if sources[name] == nil {
                sources[name] = track.formID
            }
        }
        runtimeState.conditionSourceFormIDs = sources
        return sources
    }

    /// Music record index off the streamer's cell provider, which is where
    /// every decoded record store this session built lives.
    private var runtimeStateMusicStore: MusicRecordStore? {
        (worldData as? AudioDataProviding)?.musicStore
    }
}
