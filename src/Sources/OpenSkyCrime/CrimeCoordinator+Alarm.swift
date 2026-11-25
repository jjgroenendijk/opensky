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
            AlarmSteps(owner: self).join(key, crime: id)
        }
        AlarmSteps(owner: self).broadcast(id)
    }

    /// One tick of `seconds` real time for every Alarm package.
    func advanceAlarms(by seconds: Double) {
        AlarmSteps(owner: self).advanceAlarms(by: seconds)
    }

    // MARK: - Hearing

    /// The factions in the `CRGR` form list of `faction`.
    func sharedCrimeFactions(of faction: ReferenceKey) -> Set<ReferenceKey> {
        AlarmSteps(owner: self).sharedCrimeFactions(of: faction)
    }

    // MARK: - Joining and deciding

    // MARK: - Steps

    // MARK: - Reads
}

extension CrimeCoordinator {
    /// A theft or a caught pickpocket by the player sets or clears the theft mark.
    func noteTheftMark() {
        AlarmSteps(owner: self).noteTheftMark()
    }

    /// A caught pickpocket: the target says its line. A faction that ignores
    /// pickpocketing charges nothing, and the target lets it go.
    func reactToPickpocket(_ event: CrimeEvent, outcome: CrimeOutcome) {
        AlarmSteps(owner: self).reactToPickpocket(event, outcome: outcome)
    }
}

extension CrimeCoordinator {
    public var alarmReadout: CrimeAlarmReadout {
        AlarmSteps(owner: self).alarmReadout
    }
}

extension CrimeCoordinator {
    /// Runs the alarm: who hears a crime, who joins, takes back, or pursues.
    struct AlarmSteps {
        let owner: CrimeCoordinator

        func advanceAlarms(by seconds: Double) {
            let world = owner.world
            guard !owner.alarm.witnesses.isEmpty || !owner.alarm.fighters.isEmpty else { return }
            let feet = Dictionary(
                world.livingActors().map { ($0.key, $0.feet) },
                uniquingKeysWith: { first, _ in first }
            )
            for key in owner.alarm.witnesses.keys.sorted() {
                guard let witness = owner.alarm.witnesses[key] else { continue }
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

        func broadcast(_ id: Int) {
            let world = owner.world
            guard
                let crime = owner.alarm.crimes[id], crime.takenBy == nil,
                let origin = criminalFeet(crime.criminal)
            else { return }
            let followers = Set(world.playerFollowers())
            for observer in world.livingActors() {
                let key = observer.key
                guard
                    key != crime.criminal, key != .player, !followers.contains(key),
                    runsNoOtherAlarm(key, criminal: crime.criminal, crime: id),
                    !world.isInCombat(key),
                    let current = owner.alarm.crimes[id],
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
        func runsNoOtherAlarm(_ key: ReferenceKey, criminal: ReferenceKey, crime: Int) -> Bool {
            guard let witness = owner.alarm.witnesses[key] else { return true }
            return !witness.crimes.contains(crime) && owner.alarm.criminal(of: witness) == criminal
        }

        func hearer(_ key: ReferenceKey, distance: Float, crime: AlarmCrime) -> AlarmHearer {
            let world = owner.world
            let profile = world.socialProfile(of: key)
            let crimeFaction = profile?.crimeFaction
            return AlarmHearer(
                distance: distance,
                policedFaction: owner.policedFaction(of: key),
                crimeFaction: crimeFaction,
                sharedCrimeFactions: crimeFaction.map(owner.sharedCrimeFactions(of:)) ?? [],
                isHostile: isHostile(key, toward: crime.criminal, profile: profile)
            )
        }

        func sharedCrimeFactions(of faction: ReferenceKey) -> Set<ReferenceKey> {
            let owners = owner.owners
            guard
                let resolved = owner.reporter?.runtime.factions.faction(key: faction),
                let list = resolved.faction.sharedCrimeFactionList,
                let lists = owners.formLists,
                let listID = lists.resolvedID(list, fromPlugin: resolved.sourcePlugin),
                let entries = lists.flattened(listID)?.entries
            else { return [] }
            return Set(entries.compactMap { $0.map(ReferenceKey.init(resolved:)) })
        }

        func isHostile(
            _ key: ReferenceKey, toward criminal: ReferenceKey, profile: ActorSocialProfile?
        ) -> Bool {
            let world = owner.world
            guard let profile else { return false }
            let terms = world.alarmReaction(of: key, toward: criminal)
            var reaction = CrimeAlarmRules.reaction(
                relationship: terms?.relationship, faction: terms?.faction
            )
            if
                criminal == .player,
                let faction = profile.crimeFaction, owner.guards.resisted.contains(faction)
            {
                reaction = .enemy
            }
            return CrimeAlarmRules.isHostile(
                aggression: profile.aiData.aggression,
                reaction: reaction,
                isAngry: criminal == .player && owner.alarm.angry.contains(key),
                criminalTargetsWitness: criminal != .player && owner.alarm.crimes.values.contains {
                    $0.criminal == criminal && $0.victim == key
                }
            )
        }

        func join(_ key: ReferenceKey, crime id: Int) {
            if let faction = owner.policedFaction(of: key) {
                guardTakes(key, crime: id, policing: faction)
                return
            }
            var witness = owner.alarm.witnesses[key] ?? AlarmWitness(crimes: [], role: .done)
            witness.crimes.append(id)
            owner.alarm.witnesses[key] = witness
            decide(key)
        }

        /// The first guard takes the crime, and moves its gold to its own faction when the
        /// two differ. A guard past the cap of one criminal does nothing.
        func guardTakes(
            _ guardKey: ReferenceKey,
            crime id: Int,
            policing faction: ReferenceKey
        ) {
            guard var crime = owner.alarm.crimes[id], crime.takenBy == nil else { return }
            let answering = owner.alarm.answering[crime.criminal, default: []]
            guard answering.contains(guardKey) || answering.count < CrimeAlarmRules.guardCap else {
                return
            }
            if faction != crime.faction, crime.criminal == .player {
                moveGold(of: crime, to: faction)
            }
            crime.takenBy = guardKey
            crime.faction = faction
            owner.alarm.crimes[id] = crime
            owner.alarm.answering[crime.criminal, default: []].insert(guardKey)
            var witness = owner.alarm.witnesses[guardKey] ?? AlarmWitness(crimes: [], role: .pursue)
            witness.crimes.append(id)
            witness.role = .pursue
            owner.alarm.witnesses[guardKey] = witness
            if crime.criminal != .player {
                owner.alarm.fight(guardKey, against: crime.criminal)
                sendAway(crime.criminal, from: guardKey)
                owner.refreshGuardHostility()
            }
            for (key, other) in owner.alarm.witnesses
                where key != guardKey && other.crimes.contains(id)
            {
                if other.role == .takeBack || other.role == .flee {
                    finish(key)
                }
            }
        }

        func moveGold(of crime: AlarmCrime, to faction: ReferenceKey) {
            guard let reporter = owner.reporter, crime.gold > 0 else { return }
            reporter.modifyCrimeGold(by: -crime.gold, violent: crime.violent, of: crime.faction)
            reporter.modifyCrimeGold(by: crime.gold, violent: crime.violent, of: faction)
            if let index = owner.pendingReports.firstIndex(where: {
                $0.faction == crime.faction && $0.gold == crime.gold && $0.victim == crime.victim
            }) {
                owner.pendingReports[index].faction = faction
            }
        }

        /// An NPC criminal that is not fighting runs from the guard.
        func sendAway(_ criminal: ReferenceKey, from guardKey: ReferenceKey) {
            let world = owner.world
            guard
                !world.isInCombat(criminal),
                let from = criminalFeet(criminal),
                let pursuer = world.livingActors().first(where: { $0.key == guardKey })?.feet
            else { return }
            _ = world.moveActor(criminal, to: CrimeAlarmRules.fleePoint(
                criminal: from, from: pursuer, distance: CrimeCoordinator.criminalFleeDistance
            ))
        }

        func decide(_ key: ReferenceKey) {
            let world = owner.world
            guard let witness = owner.alarm.witnesses[key], witness.role != .pursue else { return }
            for id in witness.crimes where owner.alarm.crimes[id]?.takenBy == nil {
                broadcast(id)
            }
            guard let current = owner.alarm.witnesses[key] else { return }
            let views = current.crimes.compactMap { owner.alarm.crimes[$0] }.map { crime in
                AlarmCrimeView(
                    isTaken: crime.takenBy != nil,
                    mayTakeBack: !current.gaveUpTakingBack && crime.takenBy == nil
                        && mayTakeBack(key, crime),
                    fights: CrimeAlarmRules.isLesser(crime.kind)
                        ? isHostile(
                            key,
                            toward: crime.criminal,
                            profile: world.socialProfile(of: key)
                        )
                        : crime.victim == key
                )
            }
            let decision = CrimeAlarmRules.decide(
                isGuard: false, crimes: views, theftMark: owner.alarm.theftMark.isSet
            )
            apply(decision, to: key)
        }
    }
}

extension CrimeCoordinator.AlarmSteps {
    /// The pickpocket target, the item's owner, or a member of the owning faction.
    func mayTakeBack(_ key: ReferenceKey, _ crime: AlarmCrime) -> Bool {
        let world = owner.world
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

    func apply(_ decision: (role: AlarmRole, angry: Bool), to key: ReferenceKey) {
        let world = owner.world
        guard
            var witness = owner.alarm.witnesses[key],
            let criminal = owner.alarm.criminal(of: witness)
        else {
            return
        }
        witness.role = decision.role
        witness.elapsed = 0
        owner.alarm.witnesses[key] = witness
        switch decision.role {
        case .fight:
            owner.alarm.fight(key, against: criminal)
            if decision.angry {
                owner.alarm.angry.insert(key)
            }
            owner.refreshGuardHostility()
        case .takeBack:
            world.suspendPackage(for: key)
            owner.pendingCommands.append(.sayTopic("STEA", by: key))
        case .pursue, .done, .flee:
            break
        }
        owner.lastAlarm = .decided(name: world.actorName(key), role: decision.role)
    }

    func stepTakeBack(
        _ key: ReferenceKey, _ witness: AlarmWitness, seconds: Double, feet: SIMD3<Float>?
    ) {
        let world = owner.world
        var witness = witness
        witness.elapsed += max(0, seconds)
        guard let player = world.playerFeet, let feet else { return }
        if simd_distance(feet, player) <= GuardResponseState.confrontDistance {
            takeBack(key, witness)
            return
        }
        guard witness.elapsed < CrimeAlarmRules.takeBackSeconds else {
            witness.gaveUpTakingBack = true
            owner.alarm.witnesses[key] = witness
            world.stopActor(key)
            world.resumePackage(for: key)
            decide(key)
            return
        }
        if CrimeCore.needsRepath(lastTarget: witness.lastTarget, player: player) {
            _ = world.moveActor(key, to: player)
            witness.lastTarget = player
        }
        owner.alarm.witnesses[key] = witness
    }

    /// The stolen items go back to the witness, and those crimes are deleted.
    func takeBack(_ key: ReferenceKey, _ witness: AlarmWitness) {
        let world = owner.world
        var returned = 0
        for id in witness.crimes {
            guard let crime = owner.alarm.crimes[id], mayTakeBack(key, crime) else { continue }
            if
                let item = crime.stolenItem,
                world.giveBack(item, count: crime.stolenCount, to: key)
            {
                returned += Int(crime.stolenCount)
            }
            owner.reporter?.modifyCrimeGold(
                by: -crime.gold,
                violent: crime.violent,
                of: crime.faction
            )
            owner.pendingReports.removeAll {
                $0.faction == crime.faction && $0.gold == crime.gold && $0.victim == crime
                    .victim
            }
            owner.alarm.crimes[id] = nil
        }
        owner.lastAlarm = .tookBack(name: world.actorName(key), items: returned)
        finish(key)
    }

    func stepPursuit(_ key: ReferenceKey, _ witness: AlarmWitness, seconds: Double) {
        let world = owner.world
        guard let criminal = owner.alarm.criminal(of: witness) else {
            finish(key)
            return
        }
        if criminal != .player {
            if world.isDead(criminal) {
                finish(key)
            }
            return
        }
        let owed = witness.crimes.compactMap { owner.alarm.crimes[$0]?.faction }
            .contains { owner.crimeGold(of: $0) > 0 }
        guard owed else {
            finish(key)
            return
        }
        var witness = witness
        witness.sinceLine += max(0, seconds)
        if witness.sinceLine >= CrimeAlarmRules.pursueLineSeconds, !world.isDialogueOpen {
            witness.sinceLine = 0
            owner.pendingCommands.append(.sayTopic("PURS", by: key))
        }
        owner.alarm.witnesses[key] = witness
    }

    /// Ends a witness's package and hands it back to its schedule.
    func finish(_ key: ReferenceKey) {
        let world = owner.world
        guard let witness = owner.alarm.witnesses.removeValue(forKey: key) else { return }
        if witness.role == .takeBack {
            world.stopActor(key)
            world.resumePackage(for: key)
        }
        for id in witness.crimes where !owner.alarm.witnesses.values.contains(where: {
            $0.crimes.contains(id)
        }) {
            owner.alarm.crimes[id] = nil
        }
        owner.alarm.releaseAnswering()
    }

    /// A fight ends when either side is gone, or for the player once nothing is owed.
    func dropSettledFights(living: [ReferenceKey: SIMD3<Float>]) {
        let owesNothing = (owner.reporter?.runtime.ledger().totalGold ?? 0) <= 0
        var changed = false
        for (witness, criminals) in owner.alarm.fighters {
            let kept = criminals.filter { criminal in
                criminal == .player ? !owesNothing : living[criminal] != nil
            }
            guard living[witness] == nil || kept != criminals || kept.isEmpty else { continue }
            owner.alarm.fighters[witness] = living[witness] == nil || kept.isEmpty ? nil : kept
            changed = true
        }
        if changed {
            owner.refreshGuardHostility()
        }
    }

    func criminalFeet(_ criminal: ReferenceKey) -> SIMD3<Float>? {
        let world = owner.world
        return criminal == .player
            ? world.playerFeet
            : world.livingActors().first { $0.key == criminal }?.feet
    }

    func noteTheftMark() {
        let world = owner.world
        let day = Int((world.gameSeconds ?? 0) / 86400)
        owner.alarm.theftMark.note(day: day)
    }

    func reactToPickpocket(_ event: CrimeEvent, outcome: CrimeOutcome) {
        guard event.kind == .pickpocket, event.perpetrator == .player, let target = event.victim
        else { return }
        if outcome.refusal == .factionIgnoresKind {
            owner.pendingCommands.append(.sayTopic("PICN", by: target))
            return
        }
        owner.pendingCommands.append(.sayTopic("PICC", by: target))
        owner.noteTheftMark()
    }

    var alarmReadout: CrimeAlarmReadout {
        let owners = owner.owners
        let world = owner.world
        var readout = CrimeAlarmReadout(
            witnesses: owner.alarm.witnesses.keys.sorted().compactMap { key in
                owner.alarm.witnesses[key].map {
                    CrimeAlarmReadout.Witness(
                        key: key, role: $0.role.rawValue,
                        criminal: owner.alarm.criminal(of: $0),
                        crimes: $0.crimes.count
                    )
                }
            },
            fighters: owner.alarm.fighters.keys.sorted().map {
                CrimeAlarmReadout.Fighter(
                    witness: $0, criminals: (owner.alarm.fighters[$0] ?? []).sorted()
                )
            },
            angry: owner.alarm.angry.sorted(),
            theftMarkDay: owner.alarm.theftMark.day,
            openCrimes: owner.alarm.crimes.count,
            last: owner.lastAlarm.text,
            jail: owner.jailStay,
            jailFollowers: owner.jailFollowers
        )
        readout.trespass = CrimeAlarmReadout.Trespass(
            isTrespassing: owner.isPlayerTrespassing,
            isWarnedToLeave: owner.isPlayerWarnedToLeave,
            isCellOpened: owners.isCellOpened(at: world.currentCellLocation)
        )
        return readout
    }
}
