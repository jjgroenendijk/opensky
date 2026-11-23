// Carries out the alarm: it reads each hearer from the world, runs the rules in
// `CrimeAlarmRules`, and moves, speaks, and fights for the result.
// See docs/engine/crime-reports.md#the-alarm.

public import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

extension CrimeCoordinator {
    /// Where a guard sends an NPC criminal that is not fighting. Not measured.
    static let criminalFleeDistance: Float = 2000

    /// A seen crime's alarm. `direct` get it without the hearing tests.
    func raiseAlarm(
        _ event: CrimeEvent, faction: ReferenceKey, gold: Int32, direct: [ReferenceKey]
    ) {
        let id = alarm.add(event, faction: faction, gold: gold)
        for key in direct where key != event.perpetrator && key != .player && !world.isDead(key) {
            join(key, crime: id)
        }
        broadcast(id)
    }

    /// One tick of `seconds` real time for every Alarm package.
    func advanceAlarms(by seconds: Double) {
        guard !alarm.witnesses.isEmpty || !alarm.fighters.isEmpty else { return }
        let feet = Dictionary(
            world.livingActors().map { ($0.key, $0.feet) }, uniquingKeysWith: { first, _ in first }
        )
        for key in alarm.witnesses.keys.sorted() {
            guard let witness = alarm.witnesses[key] else { continue }
            if world.isDead(key) || feet[key] == nil {
                finish(key)
                continue
            }
            switch witness.role {
            case .takeBack: stepTakeBack(key, witness, seconds: seconds, feet: feet[key])
            case .pursue: stepPursuit(key, witness, seconds: seconds)
            case .fight, .done, .flee: finish(key)
            }
        }
        dropSettledFights(living: feet)
    }

    // MARK: - Hearing

    private func broadcast(_ id: Int) {
        guard
            let crime = alarm.crimes[id], crime.takenBy == nil,
            let origin = criminalFeet(crime.criminal)
        else { return }
        let followers = Set(world.playerFollowers())
        for observer in world.livingActors() {
            let key = observer.key
            guard
                key != crime.criminal, key != .player, !followers.contains(key),
                runsNoOtherAlarm(key, criminal: crime.criminal, crime: id),
                !world.isInCombat(key),
                let current = alarm.crimes[id],
                CrimeAlarmRules.hears(
                    hearer(key, distance: simd_distance(observer.feet, origin), crime: current),
                    current
                )
            else { continue }
            join(key, crime: id)
        }
    }

    /// An actor already running an alarm against another criminal, or holding this
    /// crime, does not hear it again.
    private func runsNoOtherAlarm(_ key: ReferenceKey, criminal: ReferenceKey, crime: Int) -> Bool {
        guard let witness = alarm.witnesses[key] else { return true }
        return !witness.crimes.contains(crime) && alarm.criminal(of: witness) == criminal
    }

    private func hearer(_ key: ReferenceKey, distance: Float, crime: AlarmCrime) -> AlarmHearer {
        let profile = world.socialProfile(of: key)
        let crimeFaction = profile?.crimeFaction
        return AlarmHearer(
            distance: distance,
            policedFaction: policedFaction(of: key),
            crimeFaction: crimeFaction,
            sharedCrimeFactions: crimeFaction.map(sharedCrimeFactions(of:)) ?? [],
            isHostile: isHostile(key, toward: crime.criminal, profile: profile)
        )
    }

    /// The factions in the `CRGR` form list of `faction`.
    func sharedCrimeFactions(of faction: ReferenceKey) -> Set<ReferenceKey> {
        guard
            let resolved = reporter?.runtime.factions.faction(key: faction),
            let list = resolved.faction.sharedCrimeFactionList,
            let lists = owners.formLists,
            let listID = lists.resolvedID(list, fromPlugin: resolved.sourcePlugin),
            let entries = lists.flattened(listID)?.entries
        else { return [] }
        return Set(entries.compactMap { $0.map(ReferenceKey.init(resolved:)) })
    }

    private func isHostile(
        _ key: ReferenceKey, toward criminal: ReferenceKey, profile: ActorSocialProfile?
    ) -> Bool {
        guard let profile else { return false }
        let terms = world.alarmReaction(of: key, toward: criminal)
        var reaction = CrimeAlarmRules.reaction(
            relationship: terms?.relationship, faction: terms?.faction
        )
        if
            criminal == .player,
            let faction = profile.crimeFaction, guards.resisted.contains(faction)
        {
            reaction = .enemy
        }
        return CrimeAlarmRules.isHostile(
            aggression: profile.aiData.aggression,
            reaction: reaction,
            isAngry: criminal == .player && alarm.angry.contains(key),
            criminalTargetsWitness: criminal != .player && alarm.crimes.values.contains {
                $0.criminal == criminal && $0.victim == key
            }
        )
    }

    // MARK: - Joining and deciding

    private func join(_ key: ReferenceKey, crime id: Int) {
        if let faction = policedFaction(of: key) {
            guardTakes(key, crime: id, policing: faction)
            return
        }
        var witness = alarm.witnesses[key] ?? AlarmWitness(crimes: [], role: .done)
        witness.crimes.append(id)
        alarm.witnesses[key] = witness
        decide(key)
    }

    /// The first guard takes the crime, and moves its gold to its own faction when the
    /// two differ. A guard past the cap of one criminal does nothing.
    private func guardTakes(
        _ guardKey: ReferenceKey,
        crime id: Int,
        policing faction: ReferenceKey
    ) {
        guard var crime = alarm.crimes[id], crime.takenBy == nil else { return }
        let answering = alarm.answering[crime.criminal, default: []]
        guard answering.contains(guardKey) || answering.count < CrimeAlarmRules.guardCap else {
            return
        }
        if faction != crime.faction, crime.criminal == .player {
            moveGold(of: crime, to: faction)
        }
        crime.takenBy = guardKey
        crime.faction = faction
        alarm.crimes[id] = crime
        alarm.answering[crime.criminal, default: []].insert(guardKey)
        var witness = alarm.witnesses[guardKey] ?? AlarmWitness(crimes: [], role: .pursue)
        witness.crimes.append(id)
        witness.role = .pursue
        alarm.witnesses[guardKey] = witness
        if crime.criminal != .player {
            alarm.fight(guardKey, against: crime.criminal)
            sendAway(crime.criminal, from: guardKey)
            refreshGuardHostility()
        }
        for (key, other) in alarm.witnesses where key != guardKey && other.crimes.contains(id) {
            if other.role == .takeBack || other.role == .flee {
                finish(key)
            }
        }
    }

    private func moveGold(of crime: AlarmCrime, to faction: ReferenceKey) {
        guard let reporter, crime.gold > 0 else { return }
        reporter.modifyCrimeGold(by: -crime.gold, violent: crime.violent, of: crime.faction)
        reporter.modifyCrimeGold(by: crime.gold, violent: crime.violent, of: faction)
        if let index = pendingReports.firstIndex(where: {
            $0.faction == crime.faction && $0.gold == crime.gold && $0.victim == crime.victim
        }) {
            pendingReports[index].faction = faction
        }
    }

    /// An NPC criminal that is not fighting runs from the guard.
    private func sendAway(_ criminal: ReferenceKey, from guardKey: ReferenceKey) {
        guard
            !world.isInCombat(criminal),
            let from = criminalFeet(criminal),
            let pursuer = world.livingActors().first(where: { $0.key == guardKey })?.feet
        else { return }
        _ = world.moveActor(criminal, to: CrimeAlarmRules.fleePoint(
            criminal: from, from: pursuer, distance: Self.criminalFleeDistance
        ))
    }

    private func decide(_ key: ReferenceKey) {
        guard let witness = alarm.witnesses[key], witness.role != .pursue else { return }
        for id in witness.crimes where alarm.crimes[id]?.takenBy == nil {
            broadcast(id)
        }
        guard let current = alarm.witnesses[key] else { return }
        let views = current.crimes.compactMap { alarm.crimes[$0] }.map { crime in
            AlarmCrimeView(
                isTaken: crime.takenBy != nil,
                mayTakeBack: !current.gaveUpTakingBack && crime.takenBy == nil
                    && mayTakeBack(key, crime),
                fights: CrimeAlarmRules.isLesser(crime.kind)
                    ? isHostile(key, toward: crime.criminal, profile: world.socialProfile(of: key))
                    : crime.victim == key
            )
        }
        let decision = CrimeAlarmRules.decide(
            isGuard: false, crimes: views, theftMark: alarm.theftMark.isSet
        )
        apply(decision, to: key)
    }

    /// The pickpocket target, the item's owner, or a member of the owning faction.
    private func mayTakeBack(_ key: ReferenceKey, _ crime: AlarmCrime) -> Bool {
        guard
            crime.criminal == .player, crime.kind == .theft || crime.kind == .pickpocket,
            let owner = crime.victim
        else { return false }
        if owner == key || crime.kind == .pickpocket {
            return owner == key
        }
        let profile = world.socialProfile(of: key)
        return profile?.base.map(ReferenceKey.init(resolved:)) == owner
            || profile?.memberships.isMember(of: owner) == true
    }

    private func apply(_ decision: (role: AlarmRole, angry: Bool), to key: ReferenceKey) {
        guard var witness = alarm.witnesses[key], let criminal = alarm.criminal(of: witness) else {
            return
        }
        witness.role = decision.role
        witness.elapsed = 0
        alarm.witnesses[key] = witness
        switch decision.role {
        case .fight:
            alarm.fight(key, against: criminal)
            if decision.angry {
                alarm.angry.insert(key)
            }
            refreshGuardHostility()
        case .takeBack:
            world.suspendPackage(for: key)
            pendingCommands.append(.sayTopic("STEA", by: key))
        case .pursue, .done, .flee:
            break
        }
        lastAlarm = .decided(name: world.actorName(key), role: decision.role)
    }

    // MARK: - Steps

    private func stepTakeBack(
        _ key: ReferenceKey, _ witness: AlarmWitness, seconds: Double, feet: SIMD3<Float>?
    ) {
        var witness = witness
        witness.elapsed += max(0, seconds)
        guard let player = world.playerFeet, let feet else { return }
        if simd_distance(feet, player) <= GuardResponseState.confrontDistance {
            takeBack(key, witness)
            return
        }
        guard witness.elapsed < CrimeAlarmRules.takeBackSeconds else {
            witness.gaveUpTakingBack = true
            alarm.witnesses[key] = witness
            world.stopActor(key)
            world.resumePackage(for: key)
            decide(key)
            return
        }
        if CrimeCore.needsRepath(lastTarget: witness.lastTarget, player: player) {
            _ = world.moveActor(key, to: player)
            witness.lastTarget = player
        }
        alarm.witnesses[key] = witness
    }

    /// The stolen items go back to the witness, and those crimes are deleted.
    private func takeBack(_ key: ReferenceKey, _ witness: AlarmWitness) {
        var returned = 0
        for id in witness.crimes {
            guard let crime = alarm.crimes[id], mayTakeBack(key, crime) else { continue }
            if
                let item = crime.stolenItem,
                world.giveBack(item, count: crime.stolenCount, to: key)
            {
                returned += Int(crime.stolenCount)
            }
            reporter?.modifyCrimeGold(by: -crime.gold, violent: crime.violent, of: crime.faction)
            pendingReports.removeAll {
                $0.faction == crime.faction && $0.gold == crime.gold && $0.victim == crime.victim
            }
            alarm.crimes[id] = nil
        }
        lastAlarm = .tookBack(name: world.actorName(key), items: returned)
        finish(key)
    }

    private func stepPursuit(_ key: ReferenceKey, _ witness: AlarmWitness, seconds: Double) {
        guard let criminal = alarm.criminal(of: witness) else {
            finish(key)
            return
        }
        if criminal != .player {
            if world.isDead(criminal) {
                finish(key)
            }
            return
        }
        let owed = witness.crimes.compactMap { alarm.crimes[$0]?.faction }
            .contains { crimeGold(of: $0) > 0 }
        guard owed else {
            finish(key)
            return
        }
        var witness = witness
        witness.sinceLine += max(0, seconds)
        if witness.sinceLine >= CrimeAlarmRules.pursueLineSeconds, !world.isDialogueOpen {
            witness.sinceLine = 0
            pendingCommands.append(.sayTopic("PURS", by: key))
        }
        alarm.witnesses[key] = witness
    }

    /// Ends a witness's package and hands it back to its schedule.
    private func finish(_ key: ReferenceKey) {
        guard let witness = alarm.witnesses.removeValue(forKey: key) else { return }
        if witness.role == .takeBack {
            world.stopActor(key)
            world.resumePackage(for: key)
        }
        for id in witness.crimes where !alarm.witnesses.values.contains(where: {
            $0.crimes.contains(id)
        }) {
            alarm.crimes[id] = nil
        }
    }

    /// A fight ends when either side is gone, or for the player once nothing is owed.
    private func dropSettledFights(living: [ReferenceKey: SIMD3<Float>]) {
        let owesNothing = (reporter?.runtime.ledger().totalGold ?? 0) <= 0
        var changed = false
        for (witness, criminals) in alarm.fighters {
            let kept = criminals.filter { criminal in
                criminal == .player ? !owesNothing : living[criminal] != nil
            }
            guard living[witness] == nil || kept != criminals || kept.isEmpty else { continue }
            alarm.fighters[witness] = living[witness] == nil || kept.isEmpty ? nil : kept
            changed = true
        }
        if changed {
            refreshGuardHostility()
        }
    }

    // MARK: - Reads

    private func criminalFeet(_ criminal: ReferenceKey) -> SIMD3<Float>? {
        criminal == .player
            ? world.playerFeet
            : world.livingActors().first { $0.key == criminal }?.feet
    }
}

extension CrimeCoordinator {
    /// A theft or a caught pickpocket by the player sets or clears the theft mark.
    func noteTheftMark() {
        let day = Int((world.gameSeconds ?? 0) / 86400)
        alarm.theftMark.note(day: day)
    }

    /// A caught pickpocket: the target says its line. A faction that ignores
    /// pickpocketing charges nothing, and the target lets it go.
    func reactToPickpocket(_ event: CrimeEvent, outcome: CrimeOutcome) {
        guard event.kind == .pickpocket, event.perpetrator == .player, let target = event.victim
        else { return }
        if outcome.refusal == .factionIgnoresKind {
            pendingCommands.append(.sayTopic("PICN", by: target))
            return
        }
        pendingCommands.append(.sayTopic("PICC", by: target))
        noteTheftMark()
    }
}

extension CrimeCoordinator {
    public var alarmReadout: CrimeAlarmReadout {
        CrimeAlarmReadout(
            witnesses: alarm.witnesses.keys.sorted().compactMap { key in
                alarm.witnesses[key].map {
                    CrimeAlarmReadout.Witness(
                        key: key, role: $0.role.rawValue, criminal: alarm.criminal(of: $0),
                        crimes: $0.crimes.count
                    )
                }
            },
            fighters: alarm.fighters.keys.sorted().map {
                CrimeAlarmReadout.Fighter(
                    witness: $0, criminals: (alarm.fighters[$0] ?? []).sorted()
                )
            },
            angry: alarm.angry.sorted(),
            theftMarkDay: alarm.theftMark.day,
            openCrimes: alarm.crimes.count,
            last: lastAlarm.text,
            jail: jailStay,
            jailFollowers: jailFollowers
        )
    }
}
