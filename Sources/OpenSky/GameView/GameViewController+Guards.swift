// Session wiring for guard response (issue #505, roadmap item 21.6): each world
// tick, guards who see a player they have a bounty against walk up and open
// the arrest conversation or, past the attack-on-sight line, turn hostile; an
// arrest outcome settles the ledger, the inventory, the clock and the player's
// placement.
//
// The decisions are engine types — `GuardResponseState`, `CrimeResponsePolicy`,
// `GuardCrimeHostility`, `CrimeArrest` — so they build into `openskycli` and
// are testable without a window. This satellite only gathers what they read
// and carries out what they return.
//
// ## What is paid per tick
//
// Nothing beyond a ledger read while the player owes nobody, which is almost
// always. With a bounty, the pass reads the perception pass's converged
// detections (no raycast), builds a profile for each detecting observer, and
// repaths a pursuing guard only once the player has moved away from where it
// was last sent.
//
// The arrest conversation is the load order's own guard dialogue, opened with
// `beginDialogue(with:)`; its fragments reach the outcome through the
// `PlayerPayCrimeGold` and `SendPlayerToJail` natives. A conversation that
// closes with the bounty still owed is resisting arrest — "If you cancel the
// dialogue when guards attempt to arrest you, they will attack you"
// (<https://en.uesp.net/wiki/Skyrim:Crime>).

import AppKit
import OpenSkyEngine
import OpenSkyFormats
import OpenSkyGameData
import simd

extension GameViewController {
    /// How far the player may move from a pursuing guard's last destination
    /// before the guard repaths, in world units. Half the confrontation
    /// distance, so a guard never arrives somewhere the player was a whole
    /// conversation's reach ago.
    static let guardRepathDistance: Float = GuardResponseState.confrontDistance / 2

    /// One tick of guard response, run after the perception pass.
    func advanceGuardResponse() {
        guard let runtime = crime.reporter?.runtime, let renderer else { return }
        let now = renderer.gameClock.totalGameSeconds
        finishGuardConversationIfClosed(runtime: runtime, now: now)
        let ledger = runtime.ledger()
        forgiveSettledFactions(ledger: ledger)
        refreshGuardHostility(ledger: ledger)
        guard ledger.totalGold > 0, !dialogue.isOpen else {
            releasePursuers(except: nil)
            return
        }
        let actions = crime.guards.actions(
            guards: guardCandidates(),
            bounty: { runtime.crimeGold(of: $0) },
            values: { runtime.factions.faction(key: $0)?.faction.crimeValues },
            now: now
        )
        releasePursuers(except: actions.first.map(Self.guardKey(of:)))
        for action in actions {
            carryOut(action, now: now)
        }
    }

    /// The guard faction every crime faction's guards belong to, and what the
    /// hostility derivation reads about the player's bounties.
    func refreshGuardHostility(ledger: CrimeLedgerState) {
        guard let runtime = crime.reporter?.runtime else { return }
        var bounties: [ReferenceKey: Int32] = [:]
        var values: [ReferenceKey: Faction.CrimeValues] = [:]
        for entry in ledger.entries where entry.gold > 0 {
            bounties[entry.faction] = entry.gold
            values[entry.faction] = runtime.factions.faction(key: entry.faction)?
                .faction.crimeValues
        }
        factions.runtime?.derivation.crime = GuardCrimeHostility(
            guardFaction: runtime.factions.guardFactionKey,
            bounties: bounties,
            crimeValues: values,
            resisted: crime.guards.resisted
        )
    }

    /// The player refused arrest with `faction`: every one of its guards turns
    /// hostile. The dev panel's resist control and a closed arrest
    /// conversation both come through here.
    func resistArrest(with faction: ReferenceKey) {
        let now = renderer?.gameClock.totalGameSeconds ?? 0
        if case let .confront(guardKey, _, _) = crime.guards.active {
            resumePackage(for: guardKey)
        }
        crime.guards.resist(faction, now: now)
        crime.lastGuardText = "Resisted arrest with \(crimeFactionName(faction))."
        if let runtime = crime.reporter?.runtime {
            refreshGuardHostility(ledger: runtime.ledger())
        }
    }

    // MARK: - Private

    /// Every detecting observer that polices a faction, with its distance.
    private func guardCandidates() -> [GuardCandidate] {
        guard
            let perception = perception.runtime,
            let guardFaction = crime.reporter?.runtime.factions.guardFactionKey,
            let player = renderer?.locomotion.status.feetPosition
        else { return [] }
        let detecting = Set(perception.observersDetecting(.player))
        return combatActors().compactMap { actor in
            guard
                !actor.isDead,
                detecting.contains(actor.key),
                let profile = socialProfile(of: actor.key),
                let faction = GuardRecognition.policedFaction(
                    of: profile, guardFaction: guardFaction
                )
            else { return nil }
            return GuardCandidate(
                guardKey: actor.key,
                crimeFaction: faction,
                detectsPlayer: true,
                distance: simd_distance(actor.feet, player)
            )
        }
    }

    private func carryOut(_ action: GuardAction, now: Double) {
        switch action {
        case let .pursue(guardKey, faction):
            pursue(guardKey, crimeFaction: faction)
        case let .confront(guardKey, faction, bounty):
            _ = streamer?.stopActor(guardKey)
            crime.pursuitTargets[guardKey] = nil
            crime.guards.begin(action)
            beginDialogue(with: guardKey)
            guard dialogue.isOpen else {
                // No dialogue index, or the menu refused: hold this guard off
                // rather than retrying every frame.
                crime.guards.end(settled: false, now: now)
                resumePackage(for: guardKey)
                crime.lastGuardText = "Guard could not open the arrest conversation "
                    + "(\(dialogue.lastOutcome ?? "no reason given"))."
                return
            }
            crime.lastGuardText = "Guard confronted the player over a \(bounty) bounty "
                + "with \(crimeFactionName(faction))."
        }
    }

    private func pursue(_ guardKey: ReferenceKey, crimeFaction faction: ReferenceKey) {
        guard let streamer, let player = renderer?.locomotion.status.feetPosition else { return }
        if
            let target = crime.pursuitTargets[guardKey],
            simd_distance(target, player) < Self.guardRepathDistance
        {
            return
        }
        packages.runtime?.setSuspended(true, actor: guardKey)
        let result = streamer.moveActor(guardKey, to: player)
        crime.pursuitTargets[guardKey] = player
        crime.lastGuardText = "Guard of \(crimeFactionName(faction)) pursuing: \(result)."
    }

    /// Hands every pursuing guard but `kept` back to its package.
    private func releasePursuers(except kept: ReferenceKey?) {
        for guardKey in crime.pursuitTargets.keys where guardKey != kept {
            crime.pursuitTargets[guardKey] = nil
            _ = streamer?.stopActor(guardKey)
            resumePackage(for: guardKey)
        }
    }

    /// Settles the open confrontation once its conversation has closed.
    private func finishGuardConversationIfClosed(runtime: CrimeRuntime, now: Double) {
        guard
            !dialogue.isOpen,
            case let .confront(guardKey, faction, _) = crime.guards.active
        else { return }
        if runtime.crimeGold(of: faction) > 0 {
            resistArrest(with: faction)
        } else {
            crime.guards.end(settled: true, now: now)
            resumePackage(for: guardKey)
        }
    }

    /// A faction the player no longer owes stops holding the resistance
    /// against them.
    private func forgiveSettledFactions(ledger: CrimeLedgerState) {
        for faction in crime.guards.resisted where ledger.gold(for: faction) <= 0 {
            crime.guards.forgive(faction)
        }
    }

    func crimeFactionName(_ faction: ReferenceKey) -> String {
        crime.reporter?.runtime.factions.faction(key: faction)?.displayName
            ?? faction.description
    }

    private static func guardKey(of action: GuardAction) -> ReferenceKey {
        switch action {
        case let .pursue(guardKey, _), let .confront(guardKey, _, _): guardKey
        }
    }
}

// MARK: - Arrest outcomes

extension GameViewController: CrimeArrestSession {
    func canPayCrimeGold(to faction: ReferenceKey) -> Bool? {
        crimeArrest()?.canPay(faction)
    }

    func settleArrest(
        with faction: ReferenceKey,
        _ outcome: ArrestOutcome
    ) -> Result<ArrestSettlement, ArrestRefusal>? {
        guard let arrest = crimeArrest() else { return nil }
        let evidence = evidenceHolder(of: faction, arrest: arrest)
        let result: Result<ArrestSettlement, ArrestRefusal> = switch outcome {
        case let .pay(removeStolen, goToJail):
            Result { () throws(ArrestRefusal) in
                try arrest.pay(
                    faction, removeStolen: removeStolen, goToJail: goToJail, evidence: evidence
                )
            }
        case .jail:
            Result { () throws(ArrestRefusal) in try arrest.jail(faction, evidence: evidence) }
        }
        switch result {
        case let .success(settlement):
            serve(settlement)
        case let .failure(refusal):
            crime.lastGuardText = "Arrest with \(crimeFactionName(faction)) refused: \(refusal)."
        }
        return result
    }

    /// The engine's arrest outcomes over this session's ledger and inventory.
    func crimeArrest() -> CrimeArrest? {
        guard
            let runtime = crime.reporter?.runtime,
            let inventory = worldItems.runtime?.inventory
        else { return nil }
        return CrimeArrest(crime: runtime, inventory: inventory)
    }

    /// The evidence chest as an inventory owner: the resident placement when
    /// the chest is streamed in, so its own `CNTO` baseline is kept, and a
    /// baseline-free holder under the same key otherwise.
    private func evidenceHolder(
        of faction: ReferenceKey,
        arrest: CrimeArrest
    ) -> InventoryHolder? {
        guard let key = arrest.evidenceChest(of: faction) else { return nil }
        if let placed = streamer?.referenceEntry(key: key)?.placedReference {
            return InventoryHolder(
                key: key,
                owner: .container(base: placed.base),
                cell: streamer?.cellLocation(of: key)
            )
        }
        return arrest.unresidentEvidence(of: faction)
    }

    /// Everything after the ledger: the sentence on the clock, the player at
    /// the release marker when it is resident, and the guards stood down.
    private func serve(_ settlement: ArrestSettlement) {
        let now = renderer?.gameClock.totalGameSeconds ?? 0
        if settlement.sentenceDays > 0, let renderer {
            renderer.gameClock = GameClock(
                totalGameSeconds: now + Double(settlement.sentenceDays) * GameClock.secondsPerDay
            )
        }
        let moved = settlement.releaseMarker.map(movePlayer(toMarker:)) ?? false
        crime.guards.forgive(settlement.faction)
        if
            case let .confront(guardKey, faction, _) = crime.guards.active,
            faction == settlement.faction
        {
            crime.guards.end(settled: true, now: now)
            resumePackage(for: guardKey)
        }
        if let runtime = crime.reporter?.runtime {
            refreshGuardHostility(ledger: runtime.ledger())
        }
        crime.lastGuardText = Self.settlementText(
            settlement,
            factionName: crimeFactionName(settlement.faction),
            moved: moved
        )
    }

    /// Puts the player on a resident marker's placement. A marker in a cell
    /// that is not streamed in is left alone: this engine has no cross-cell
    /// teleport yet, so the player stays where they are and the readout says
    /// so (docs/engine/guard-response.md).
    private func movePlayer(toMarker marker: ReferenceKey) -> Bool {
        guard
            let renderer,
            let placement = streamer?.referenceEntry(key: marker)?.placedReference?.placement
        else { return false }
        let camera = SceneCamera.teleport(placement: placement)
        renderer.camera = camera
        renderer.reseedMovement(camera: camera)
        return true
    }

    static func settlementText(
        _ settlement: ArrestSettlement,
        factionName: String,
        moved: Bool
    ) -> String {
        let seized = settlement.confiscated.reduce(0) { $0 + Int($1.count) }
        let how = settlement.sentenceDays > 0
            ? "Served \(settlement.sentenceDays) days"
            : "Paid \(settlement.goldPaid) gold"
        let placement = switch (settlement.releaseMarker, moved) {
        case (nil, _): ""
        case (_, true): ", moved to the jail marker"
        case (_, false): ", jail marker not resident"
        }
        return "\(how) to \(factionName) for a \(settlement.bounty) bounty; "
            + "\(seized) stolen items seized\(placement)."
    }
}
