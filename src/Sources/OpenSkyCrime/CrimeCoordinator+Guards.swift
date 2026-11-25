// Guard response: each world tick, guards who see a player they have a bounty
// against walk up and open the arrest conversation or, past the
// attack-on-sight line, turn hostile. The decisions are `GuardResponseState`
// and `CrimeResponsePolicy`; this file gathers what they read and runs what
// they return. See docs/engine/guard-response.md.

public import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import simd

extension CrimeCoordinator {
    /// One tick, run after the perception pass. Costs one ledger read while
    /// the player owes nobody.
    /// - Returns: what crime asked of the app this frame.
    public func advanceGuardResponse() -> [CrimeCommand] {
        stepGuardResponse()
        return takeCommands()
    }

    func stepGuardResponse() {
        GuardSteps(owner: self).stepGuardResponse()
    }

    /// Hands the player's bounties to the hostility derivation.
    func refreshGuardHostility() {
        GuardSteps(owner: self).refreshGuardHostility()
    }

    /// Every guard of `faction` turns hostile. The readout's resist control and
    /// a closed arrest conversation both come through here.
    func resistArrest(with faction: ReferenceKey) {
        GuardSteps(owner: self).resistArrest(with: faction)
    }

    // MARK: - Private
}

/// One blow between two actors, by who struck it.
struct ActorStrike: Hashable {
    let aggressor: ReferenceKey
    let target: ReferenceKey
}

extension CrimeCoordinator {
    /// An actor other than the player strikes someone a crime faction protects, and
    /// struck first: each blow raises an alarm, so up to four guards answer. A blow back
    /// is self-defense. UESP "Skyrim:Crime": "Self-defense against an unprovoked assault
    /// is legal".
    func reportActorAssault(on target: ReferenceKey, by aggressor: ReferenceKey) {
        GuardSteps(owner: self).reportActorAssault(on: target, by: aggressor)
    }
}

extension CrimeSessionWorld {
    /// Every detecting observer that polices a faction, with its distance.
    func guardCandidates(guardFaction: ReferenceKey?) -> [GuardCandidate] {
        guard let guardFaction, let player = playerFeet else { return [] }
        return actorsDetectingPlayer().compactMap { observer in
            guard
                let profile = socialProfile(of: observer.key),
                let faction = GuardRecognition.policedFaction(
                    of: profile, guardFaction: guardFaction
                )
            else { return nil }
            return GuardCandidate(
                guardKey: observer.key,
                crimeFaction: faction,
                detectsPlayer: true,
                distance: simd_distance(observer.feet, player)
            )
        }
    }

    /// A faction protects its members and the people of the places it polices.
    func protects(_ faction: ReferenceKey, _ target: ReferenceKey) -> Bool {
        guard let profile = socialProfile(of: target) else { return false }
        return profile.crimeFaction == faction
            || factionMemberships(of: target)?.isMember(of: faction) == true
    }

    func isPublicArea(_ location: CellSceneLocation?) -> Bool {
        location.map { cellTrespassFlags(at: $0).isPublicArea } ?? false
    }

    func isOffLimits(_ location: CellSceneLocation?) -> Bool {
        location.map { cellTrespassFlags(at: $0).isOffLimits } ?? false
    }
}

nonisolated extension FactionStore {
    /// The crime values of the faction `key` names, or nil.
    func crimeValues(of key: ReferenceKey) -> Faction.CrimeValues? {
        faction(key: key)?.faction.crimeValues
    }
}

extension CrimeCoordinator {
    /// Runs the guards' response to the player's crimes.
    struct GuardSteps {
        let owner: CrimeCoordinator

        func stepGuardResponse() {
            let world = owner.world
            guard let runtime = owner.reporter?.runtime, let now = world.gameSeconds else {
                return
            }
            finishConversationIfClosed(runtime: runtime, now: now)
            let ledger = runtime.ledger()
            for faction in owner.guards.resisted where ledger.gold(for: faction) <= 0 {
                owner.guards.forgive(faction)
            }
            for faction in owner.guards.expiredResistance(now: now) {
                owner.guards.forgive(faction)
            }
            owner.refreshGuardHostility()
            guard ledger.totalGold > 0, !world.isDialogueOpen else {
                releasePursuers(except: nil)
                return
            }
            let actions = owner.guards.actions(
                guards: world.guardCandidates(
                    guardFaction: owner.reporter?.runtime.factions.guardFactionKey
                ),
                bounty: { ledger.entry(for: $0) },
                values: { runtime.factions.crimeValues(of: $0) },
                settings: runtime.settings,
                now: now
            )
            releasePursuers(except: actions.first.map(CrimeCore.guardKey(of:)))
            for action in actions {
                carryOut(action, now: now)
            }
        }

        func refreshGuardHostility() {
            guard let runtime = owner.reporter?.runtime else { return }
            owner.pendingCommands.append(.applyGuardHostility(CrimeCore.guardHostility(
                ledger: runtime.ledger(), factions: runtime.factions,
                resisted: owner.guards.resisted,
                settings: runtime.settings, alarmFighters: owner.alarm.fighters
            )))
        }

        func resistArrest(with faction: ReferenceKey) {
            let world = owner.world
            if case let .confront(guardKey, _, _) = owner.guards.active {
                world.resumePackage(for: guardKey)
            }
            owner.guards.resist(faction, now: world.gameSeconds ?? 0)
            owner.lastGuard = .resisted(faction: owner.factionName(faction))
            owner.refreshGuardHostility()
        }

        func carryOut(_ action: GuardAction, now: Double) {
            switch action {
            case let .pursue(guardKey, faction):
                pursue(guardKey, crimeFaction: faction)
            case let .confront(guardKey, faction, bounty):
                confront(guardKey, crime: (faction, bounty), action: action, now: now)
            }
        }

        func confront(
            _ guardKey: ReferenceKey,
            crime: (faction: ReferenceKey, bounty: Int32),
            action: GuardAction,
            now: Double
        ) {
            let world = owner.world
            world.stopActor(guardKey)
            owner.pursuitTargets[guardKey] = nil
            owner.guards.begin(action)
            world.beginDialogue(with: guardKey)
            guard world.isDialogueOpen else {
                // No dialogue index, or the menu refused: hold this guard off
                // rather than retrying every frame.
                owner.guards.end(settled: false, now: now)
                world.resumePackage(for: guardKey)
                owner.lastGuard = .conversationFailed(reason: world.lastDialogueOutcome)
                return
            }
            owner.lastGuard = .confronted(
                bounty: crime.bounty,
                faction: owner.factionName(crime.faction)
            )
        }

        func pursue(_ guardKey: ReferenceKey, crimeFaction faction: ReferenceKey) {
            let world = owner.world
            guard let player = world.playerFeet, CrimeCore.needsRepath(
                lastTarget: owner.pursuitTargets[guardKey],
                player: player
            ) else {
                return
            }
            world.suspendPackage(for: guardKey)
            guard let result = world.moveActor(guardKey, to: player) else { return }
            owner.pursuitTargets[guardKey] = player
            owner.lastGuard = .pursuing(faction: owner.factionName(faction), move: result)
        }

        /// Hands every pursuing guard but `kept` back to its package.
        func releasePursuers(except kept: ReferenceKey?) {
            let world = owner.world
            for guardKey in owner.pursuitTargets.keys where guardKey != kept {
                owner.pursuitTargets[guardKey] = nil
                world.stopActor(guardKey)
                world.resumePackage(for: guardKey)
            }
        }

        /// A conversation that closes with the bounty still owed is resisting
        /// arrest (<https://en.uesp.net/wiki/Skyrim:Crime>). One that closes with it
        /// cleared, without a fine or jail, sent the guard away quietly.
        func finishConversationIfClosed(runtime: CrimeRuntime, now: Double) {
            let world = owner.world
            guard
                world.isDialogueOpen == false,
                case let .confront(guardKey, faction, _) = owner.guards.active
            else { return }
            if runtime.crimeGold(of: faction) > 0 {
                owner.resistArrest(with: faction)
            } else {
                owner.guards.end(settled: true, now: now)
                world.resumePackage(for: guardKey)
                // A bribe, a Thane's status, or the Thieves Guild sent the guard away
                // quietly, so the victims forget the catch (UESP "Skyrim:Pickpocket").
                owner.pendingCommands.append(.settlePickpocketCatches(faction, forgotten: true))
            }
        }

        func reportActorAssault(on target: ReferenceKey, by aggressor: ReferenceKey) {
            let world = owner.world
            guard target != aggressor, aggressor != .player else { return }
            let strike = ActorStrike(aggressor: aggressor, target: target)
            let answered = ActorStrike(aggressor: target, target: aggressor)
            guard
                !owner.actorFirstStrikes.contains(answered),
                owner.policedFaction(of: aggressor) == nil,
                let faction = owner
                    .crimeFaction(in: owner.crimeCell(of: target) ?? world.currentCellLocation),
                target == .player || world.protects(faction, target)
            else { return }
            owner.actorFirstStrikes.insert(strike)
            owner.raiseAlarm(
                CrimeEvent(
                    kind: .assault, perpetrator: aggressor, victim: target, crimeFaction: faction,
                    witnessed: true
                ),
                faction: faction, gold: 0, direct: target == .player ? [] : [target]
            )
            owner.lastGuard = .actorCriminal(
                name: world.actorName(aggressor),
                faction: owner.factionName(faction)
            )
            owner.refreshGuardHostility()
        }
    }
}
