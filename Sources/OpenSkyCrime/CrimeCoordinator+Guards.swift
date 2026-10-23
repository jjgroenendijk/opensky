// Guard response: each world tick, guards who see a player they have a bounty
// against walk up and open the arrest conversation or, past the
// attack-on-sight line, turn hostile. The decisions are `GuardResponseState`
// and `CrimeResponsePolicy`; this file gathers what they read and runs what
// they return. See docs/engine/guard-response.md.

import OpenSkyCrimeInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
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
        guard let runtime = reporter?.runtime, let now = world.gameSeconds else {
            return
        }
        finishConversationIfClosed(runtime: runtime, now: now)
        let ledger = runtime.ledger()
        for faction in guards.resisted where ledger.gold(for: faction) <= 0 {
            guards.forgive(faction)
        }
        refreshGuardHostility()
        guard ledger.totalGold > 0, !world.isDialogueOpen else {
            releasePursuers(except: nil)
            return
        }
        let actions = guards.actions(
            guards: guardCandidates(),
            bounty: { ledger.entry(for: $0) },
            values: { runtime.factions.faction(key: $0)?.faction.crimeValues },
            settings: runtime.settings,
            now: now
        )
        releasePursuers(except: actions.first.map(CrimeCore.guardKey(of:)))
        for action in actions {
            carryOut(action, now: now)
        }
    }

    /// Hands the player's bounties to the hostility derivation.
    public func refreshGuardHostility() {
        guard let runtime = reporter?.runtime else { return }
        pendingCommands.append(.applyGuardHostility(CrimeCore.guardHostility(
            ledger: runtime.ledger(), factions: runtime.factions, resisted: guards.resisted,
            settings: runtime.settings, actorCriminals: actorCriminals
        )))
    }

    /// Every guard of `faction` turns hostile. The readout's resist control and
    /// a closed arrest conversation both come through here.
    public func resistArrest(with faction: ReferenceKey) {
        if case let .confront(guardKey, _, _) = guards.active {
            world.resumePackage(for: guardKey)
        }
        guards.resist(faction, now: world.gameSeconds ?? 0)
        lastGuard = .resisted(faction: factionName(faction))
        refreshGuardHostility()
    }

    // MARK: - Private

    /// Every detecting observer that polices a faction, with its distance.
    private func guardCandidates() -> [GuardCandidate] {
        guard
            let guardFaction = reporter?.runtime.factions.guardFactionKey,
            let player = world.playerFeet
        else { return [] }
        return world.actorsDetectingPlayer().compactMap { observer in
            guard
                let profile = world.socialProfile(of: observer.key),
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

    private func carryOut(_ action: GuardAction, now: Double) {
        switch action {
        case let .pursue(guardKey, faction):
            pursue(guardKey, crimeFaction: faction)
        case let .confront(guardKey, faction, bounty):
            confront(guardKey, crimeFaction: faction, bounty: bounty, action: action, now: now)
        }
    }

    private func confront(
        _ guardKey: ReferenceKey,
        crimeFaction faction: ReferenceKey,
        bounty: Int32,
        action: GuardAction,
        now: Double
    ) {
        world.stopActor(guardKey)
        pursuitTargets[guardKey] = nil
        guards.begin(action)
        world.beginDialogue(with: guardKey)
        guard world.isDialogueOpen else {
            // No dialogue index, or the menu refused: hold this guard off
            // rather than retrying every frame.
            guards.end(settled: false, now: now)
            world.resumePackage(for: guardKey)
            lastGuard = .conversationFailed(reason: world.lastDialogueOutcome)
            return
        }
        lastGuard = .confronted(bounty: bounty, faction: factionName(faction))
    }

    private func pursue(_ guardKey: ReferenceKey, crimeFaction faction: ReferenceKey) {
        guard let player = world.playerFeet else { return }
        guard CrimeCore.needsRepath(lastTarget: pursuitTargets[guardKey], player: player) else {
            return
        }
        world.suspendPackage(for: guardKey)
        guard let result = world.moveActor(guardKey, to: player) else { return }
        pursuitTargets[guardKey] = player
        lastGuard = .pursuing(faction: factionName(faction), move: result)
    }

    /// Hands every pursuing guard but `kept` back to its package.
    private func releasePursuers(except kept: ReferenceKey?) {
        for guardKey in pursuitTargets.keys where guardKey != kept {
            pursuitTargets[guardKey] = nil
            world.stopActor(guardKey)
            world.resumePackage(for: guardKey)
        }
    }

    /// A conversation that closes with the bounty still owed is resisting
    /// arrest (<https://en.uesp.net/wiki/Skyrim:Crime>).
    private func finishConversationIfClosed(runtime: CrimeRuntime, now: Double) {
        guard
            world.isDialogueOpen == false,
            case let .confront(guardKey, faction, _) = guards.active
        else { return }
        if runtime.crimeGold(of: faction) > 0 {
            resistArrest(with: faction)
        } else {
            guards.end(settled: true, now: now)
            world.resumePackage(for: guardKey)
        }
    }
}

/// One blow between two actors, by who struck it.
struct ActorStrike: Hashable {
    let aggressor: ReferenceKey
    let target: ReferenceKey
}

extension CrimeCoordinator {
    /// An actor other than the player strikes first at someone a crime faction
    /// protects: its guards fight the aggressor. A blow back is self-defense. UESP
    /// "Skyrim:Crime": "Self-defense against an unprovoked assault is legal".
    func reportActorAssault(on target: ReferenceKey, by aggressor: ReferenceKey) {
        guard target != aggressor, aggressor != .player else { return }
        let strike = ActorStrike(aggressor: aggressor, target: target)
        let answered = ActorStrike(aggressor: target, target: aggressor)
        guard
            !actorFirstStrikes.contains(answered),
            actorFirstStrikes.insert(strike).inserted,
            policedFaction(of: aggressor) == nil,
            let faction = crimeFaction(in: crimeCell(of: target) ?? world.currentCellLocation),
            target == .player || protects(faction, target)
        else { return }
        actorCriminals[faction, default: []].insert(aggressor)
        lastGuard = .actorCriminal(name: world.actorName(aggressor), faction: factionName(faction))
        refreshGuardHostility()
    }

    /// A faction protects its members and the people of the places it polices.
    private func protects(_ faction: ReferenceKey, _ target: ReferenceKey) -> Bool {
        guard let profile = world.socialProfile(of: target) else { return false }
        return profile.crimeFaction == faction
            || world.factionMemberships(of: target)?.isMember(of: faction) == true
    }
}
