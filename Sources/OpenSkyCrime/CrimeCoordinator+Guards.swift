// Guard response: each world tick, guards who see a player they have a bounty
// against walk up and open the arrest conversation or, past the
// attack-on-sight line, turn hostile. The decisions are `GuardResponseState`
// and `CrimeResponsePolicy`; this file gathers what they read and runs what
// they return. See docs/engine/guard-response.md.

import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import simd

extension CrimeCoordinator {
    /// One tick, run after the perception pass. Costs one ledger read while
    /// the player owes nobody.
    public func advanceGuardResponse() {
        guard let runtime = reporter?.runtime, let world, let now = world.gameSeconds else {
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
            bounty: { runtime.crimeGold(of: $0) },
            values: { runtime.factions.faction(key: $0)?.faction.crimeValues },
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
        world?.applyGuardHostility(CrimeCore.guardHostility(
            ledger: runtime.ledger(), factions: runtime.factions, resisted: guards.resisted
        ))
    }

    /// Every guard of `faction` turns hostile. The panel's resist control and
    /// a closed arrest conversation both come through here.
    public func resistArrest(with faction: ReferenceKey) {
        if case let .confront(guardKey, _, _) = guards.active {
            world?.resumePackage(for: guardKey)
        }
        guards.resist(faction, now: world?.gameSeconds ?? 0)
        lastGuardText = "Resisted arrest with \(factionName(faction))."
        refreshGuardHostility()
    }

    // MARK: - Private

    /// Every detecting observer that polices a faction, with its distance.
    private func guardCandidates() -> [GuardCandidate] {
        guard
            let world,
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
        guard let world else { return }
        world.stopActor(guardKey)
        pursuitTargets[guardKey] = nil
        guards.begin(action)
        world.beginDialogue(with: guardKey)
        guard world.isDialogueOpen else {
            // No dialogue index, or the menu refused: hold this guard off
            // rather than retrying every frame.
            guards.end(settled: false, now: now)
            world.resumePackage(for: guardKey)
            lastGuardText = "Guard could not open the arrest conversation "
                + "(\(world.lastDialogueOutcome ?? "no reason given"))."
            return
        }
        lastGuardText = "Guard confronted the player over a \(bounty) bounty "
            + "with \(factionName(faction))."
    }

    private func pursue(_ guardKey: ReferenceKey, crimeFaction faction: ReferenceKey) {
        guard let world, let player = world.playerFeet else { return }
        guard CrimeCore.needsRepath(lastTarget: pursuitTargets[guardKey], player: player) else {
            return
        }
        world.suspendPackage(for: guardKey)
        guard let result = world.moveActor(guardKey, to: player) else { return }
        pursuitTargets[guardKey] = player
        lastGuardText = "Guard of \(factionName(faction)) pursuing: \(result)."
    }

    /// Hands every pursuing guard but `kept` back to its package.
    private func releasePursuers(except kept: ReferenceKey?) {
        for guardKey in pursuitTargets.keys where guardKey != kept {
            pursuitTargets[guardKey] = nil
            world?.stopActor(guardKey)
            world?.resumePackage(for: guardKey)
        }
    }

    /// A conversation that closes with the bounty still owed is resisting
    /// arrest (<https://en.uesp.net/wiki/Skyrim:Crime>).
    private func finishConversationIfClosed(runtime: CrimeRuntime, now: Double) {
        guard
            world?.isDialogueOpen == false,
            case let .confront(guardKey, faction, _) = guards.active
        else { return }
        if runtime.crimeGold(of: faction) > 0 {
            resistArrest(with: faction)
        } else {
            guards.end(settled: true, now: now)
            world?.resumePackage(for: guardKey)
        }
    }
}
