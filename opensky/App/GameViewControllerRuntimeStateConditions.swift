// World > Runtime State live bridge, M10.2 conditions half (issue #166): the
// first app-side consumer of `ConditionEvaluator`.
//
// Which lists are offered. MUST records are the only decoded carrier of CTDA
// conditions in the engine today (`MusicTrack.conditions`), so the panel's
// selectable sources are exactly the music tracks that author at least one
// condition. A track with no conditions is omitted rather than listed as
// trivially true, because an empty list would make the readout look like a
// verdict about something.
//
// What "the live context" means here. Globals resolve through the session's
// override layer over plugin defaults, the clock is the live game clock, and
// the subject and target are whatever the interaction ray is currently on. The
// reference index handed to the evaluator holds that one entry rather than every
// resident reference: the run-on types OpenSky resolves live are subject,
// target and reference, all of which are answered by that entry, and building a
// few-thousand-entry index on every button press to answer a single lookup would
// be waste with no observable difference.
//
// The random stream starts from `ConditionRandom`'s documented default seed on
// every evaluation, so pressing Evaluate twice on an unchanged world gives the
// same answer. That is what makes this surface usable as verification evidence.

import AppKit

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

    /// Live evaluation context: current globals, current quest state, current
    /// clock, and the reference the crosshair is on as both subject and target.
    ///
    /// The quest resolution is this session's `QuestRuntime` (issue #322).
    /// Before the quest layer was wired the four quest condition functions had
    /// no index to resolve against and every one of them reported "unresolved
    /// quest"; they now read the same state the `Quest` natives write.
    ///
    /// The alias seam is wired the same way (issue #183), and `aliasQuest` is
    /// deliberately left nil: the lists this panel evaluates are MUST record
    /// conditions, which belong to no quest, so an alias run-on in one has no
    /// quest to resolve against and reports that rather than borrowing a
    /// nearby quest's table.
    /// Item 15.8 widened the reference index from the crosshair's one entry to
    /// that entry plus every resident actor. A combat-target run-on resolves to
    /// an actor the crosshair is deliberately *not* on, so a function that needs
    /// the decoded placement — `GetIsID` — would have reported an unresolved
    /// reference for every one of them. Resident actors are tens of entries, not
    /// the few thousand the whole cell holds. The actor functions themselves
    /// need only identity and go through `ConditionCall.referenceKey()`, which
    /// is why the player answers despite having no plugin record.
    /// Also the context dialogue selection runs in (issue #205): a topic's
    /// conditions read the same globals, quest state, actors and clock this
    /// panel evaluates against, and a second builder would be a second set of
    /// answers to keep in step. `DialogueRuntime` overrides `subject`, `target`
    /// and `aliasQuest` per response, so the crosshair's reference filled in
    /// here is a default it replaces rather than a value it inherits.
    func runtimeStateConditionContext() -> ConditionContext {
        let entry = runtimeStateEntry(for: .currentTarget)
        return ConditionContext(
            globals: runtimeStateGlobalResolution(),
            quests: papyrusBridge?.questRuntime?.resolution() ?? .empty,
            aliases: papyrusBridge?.questRuntime?.aliasResolution() ?? .empty,
            actors: runtimeStateActorResolution(),
            detection: perceptionResolution(),
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

    /// The five actor condition functions' seam (issue #375): every resident
    /// actor plus the player, with the fight the combat loop derived filled in
    /// both directions.
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
            playerTarget: combat.runtime?.state.target
        )
    }

    /// One actor's values, death, hostility and draw state as a condition reads
    /// them. Only the player has a graph tracking a draw state, so every other
    /// actor carries nil and `IsWeaponOut` reports the gap.
    private func actorConditionState(
        holder: ActorValueHolder,
        values: ActorValueRuntime,
        isDead: Bool = false
    ) -> ActorConditionState {
        ActorConditionState(
            current: values.current(of: holder),
            maximums: values.baseline(of: holder).maximums,
            isDead: isDead,
            hostility: combatHostility(of: holder.key),
            combatActivity: combat.runtime?.activity(of: holder.key) ?? .notFighting,
            weaponDrawState: holder.key == .player
                ? melee.runtime?.state.drawState
                : nil
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
        (streamerCellProvider as? AudioDataProviding)?.musicStore
    }
}
