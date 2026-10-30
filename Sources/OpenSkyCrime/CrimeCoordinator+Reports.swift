// The reporting chain: a seen crime is charged at once, but it stays open until a
// witness reaches a guard. If every witness dies first, the gold comes off again. CK
// wiki "Crime": "If the last Actor who viewed a crime is killed before guards arrive,
// the crime gold is removed". A witness reaches a guard by being one, or by standing
// within `iCrimeAlarmRecDistance` of one. See docs/engine/crime.md.

import OpenSkyCrimeInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// One charged crime no guard has heard of yet.
nonisolated public struct PendingCrimeReport: Equatable, Sendable {
    public let faction: ReferenceKey
    public let gold: Int32
    public let violent: Bool
    public let witnesses: [ReferenceKey]
}

extension CrimeCoordinator {
    /// A crime that cost gold. A guard among the witnesses has it reported at once.
    func track(_ event: CrimeEvent, outcome: CrimeOutcome, witnesses: [ReferenceKey]) {
        guard
            event.perpetrator == .player, outcome.gold > 0, let faction = outcome.faction,
            !witnesses.isEmpty,
            !witnesses.contains(where: { policedFaction(of: $0) == faction })
        else { return }
        pendingReports.append(PendingCrimeReport(
            faction: faction, gold: outcome.gold, violent: event.kind.isViolent,
            witnesses: witnesses
        ))
    }

    /// One tick: delivers each report a witness carried to a guard, and takes back
    /// the gold of each report whose witnesses all died.
    public func advanceReports() {
        guard !pendingReports.isEmpty, let reporter else { return }
        let living = world.livingActors()
        let distance = reporter.runtime.settings.alarmDistance
        pendingReports = pendingReports.filter { report in
            let alive = report.witnesses.filter { !world.isDead($0) }
            guard !alive.isEmpty else {
                let removed = min(
                    report.gold,
                    reporter.runtime.crimeGold(of: report.faction, violent: report.violent)
                )
                reporter.modifyCrimeGold(by: -removed, violent: report.violent, of: report.faction)
                lastCrime = .reportLost(gold: removed, faction: factionName(report.faction))
                pendingCommands.append(.showNotice(crimeTexts.witnessKilled))
                showBountyNotice(gold: removed, added: false, faction: report.faction)
                return false
            }
            guard let witness = carrier(of: report, among: alive, living: living, distance) else {
                return true
            }
            lastCrime = .reportDelivered(
                faction: factionName(report.faction), by: world.actorName(witness)
            )
            return false
        }
    }

    /// The first living witness that stands near a guard of the report's faction.
    private func carrier(
        of report: PendingCrimeReport, among alive: [ReferenceKey],
        living: [CrimeObserver], _ distance: Float
    ) -> ReferenceKey? {
        let guards = living.filter { policedFaction(of: $0.key) == report.faction }
        guard !guards.isEmpty else { return nil }
        let positions = Dictionary(living.map { ($0.key, $0.feet) }) { first, _ in first }
        return alive.first { witness in
            guard let feet = positions[witness] else { return false }
            return guards.contains { simd_distance($0.feet, feet) <= distance }
        }
    }

    /// The crime faction `key` polices as a guard, or nil.
    func policedFaction(of key: ReferenceKey) -> ReferenceKey? {
        guard
            let guardFaction = reporter?.runtime.factions.guardFactionKey,
            let profile = world.socialProfile(of: key)
        else { return nil }
        return GuardRecognition.policedFaction(of: profile, guardFaction: guardFaction)
    }
}

extension CrimeCoordinator {
    /// The journal's crime stats (<https://ck.uesp.net/wiki/QueryStat_-_Game>). The
    /// container menu counts pickpockets itself.
    func count(_ event: CrimeEvent, outcome: CrimeOutcome) {
        guard event.perpetrator == .player else { return }
        switch event.kind {
        case .theft where !event.isPickpocket && event.stolenCount > 0:
            pendingCommands.append(.incrementStat("Items Stolen", by: event.stolenCount))
            if let faction = event.crimeFaction, event.stolenValue > 0 {
                pendingCommands.append(.stoleFromFaction(
                    faction, value: event.stolenValue, witnessed: event.witnessed
                ))
            }
        case .assault: pendingCommands.append(.incrementStat("Assaults", by: 1))
        case .murder: pendingCommands.append(.incrementStat("Murders", by: 1))
        case .trespass: pendingCommands.append(.incrementStat("Trespasses", by: 1))
        default: break
        }
        guard outcome.gold > 0, let faction = outcome.faction, let reporter else { return }
        pendingCommands.append(.incrementStat("Total Lifetime Bounty", by: outcome.gold))
        pendingCommands.append(.raiseStat("Largest Bounty", to: reporter.crimeGold(of: faction)))
    }
}
