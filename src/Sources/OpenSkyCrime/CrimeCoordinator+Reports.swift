// The 30-second window of a seen crime: until it closes, killing every witness erases the
// crime and takes the gold back. When it closes, the crime is final and sends `ADCR`. The
// clock is real time and stops while the game is paused. See docs/engine/crime-reports.md.

public import OpenSkyConditions
import OpenSkyCrimeInterface
public import OpenSkyFormatsESM
import OpenSkyGameData
import simd

/// The assault charged for the player's first blow on a victim, and the blows since.
struct AssaultBlows: Equatable {
    let outcome: CrimeOutcome
    var blows = 1
}

/// One charged crime whose witnesses can still be killed to erase it.
nonisolated public struct PendingCrimeReport: Equatable, Sendable {
    public internal(set) var faction: ReferenceKey
    public let gold: Int32
    public let violent: Bool
    public let witnesses: [ReferenceKey]
    /// What the `ADCR` event carries once the crime is final.
    public let victim: ReferenceKey?
    public let crime: StoryCrimeType
    /// Real seconds since the crime, counted only while the game runs.
    public internal(set) var age: Double = 0

    /// A crime is not checked until it is this old.
    static let firstCheck: Double = 1
    /// After this many seconds the crime is final.
    static let window: Double = 30
}

extension CrimeCoordinator {
    /// A seen crime by the player that cost gold. It stays open for the window.
    func track(_ event: CrimeEvent, outcome: CrimeOutcome, witnesses: [ReferenceKey]) {
        guard outcome.gold > 0, let faction = outcome.faction, !witnesses.isEmpty else { return }
        if event.perpetrator == .player {
            pendingReports.append(PendingCrimeReport(
                faction: faction, gold: outcome.gold, violent: event.kind.isViolent,
                witnesses: witnesses, victim: event.victim, crime: event.kind.storyCrimeType
            ))
        }
        raiseAlarm(event, faction: faction, gold: outcome.gold, direct: witnesses)
        // After the alarm, so this theft's own witnesses decide without its mark.
        if event.kind == .theft, event.perpetrator == .player, event.victim != nil {
            noteTheftMark()
        }
    }

    /// What every recorded crime changes besides the bounty: the stats, and the theft
    /// mark of a theft no witness charged.
    func recorded(_ event: CrimeEvent, outcome: CrimeOutcome) {
        count(event)
        if
            event.kind == .theft, event.perpetrator == .player, event.victim != nil,
            outcome.gold <= 0
        {
            noteTheftMark()
        }
    }

    /// One tick of `seconds` real time: erases each open crime whose witnesses all
    /// died inside the window, and makes each crime past the window final.
    public func advanceReports(by seconds: Double = 0) {
        countBountyChanges()
        advanceAlarms(by: seconds)
        guard !pendingReports.isEmpty, let reporter else { return }
        pendingReports = pendingReports.compactMap { report in
            var report = report
            report.age += max(0, seconds)
            guard report.age > PendingCrimeReport.firstCheck else { return report }
            if
                report.age < PendingCrimeReport.window,
                report.witnesses.allSatisfy({ world.isDead($0) })
            {
                erase(report, reporter: reporter)
                return nil
            }
            guard report.age >= PendingCrimeReport.window else { return report }
            storyEvents?.reportStoryEvent(.crimeGold(
                (.player, report.victim), crimeFaction: report.faction, gold: report.gold,
                crime: report.crime
            ))
            lastCrime = .reportFinal(gold: report.gold, faction: factionName(report.faction))
            return nil
        }
    }

    private func erase(_ report: PendingCrimeReport, reporter: CrimeReporter) {
        let removed = min(
            report.gold,
            reporter.runtime.crimeGold(of: report.faction, violent: report.violent)
        )
        reporter.modifyCrimeGold(by: -removed, violent: report.violent, of: report.faction)
        lastCrime = .reportLost(gold: removed, faction: factionName(report.faction))
        pendingCommands.append(.showNotice(crimeTexts.witnessKilled))
        showBountyNotice(gold: removed, added: false, faction: report.faction)
    }

    /// Takes back an assault charge: its gold, its open report, and its count.
    func withdraw(_ assault: CrimeOutcome) {
        pendingCommands.append(.incrementStat("Assaults", by: -1))
        guard let faction = assault.faction, assault.gold > 0, let reporter else { return }
        reporter.modifyCrimeGold(by: -assault.gold, violent: true, of: faction)
        if let open = pendingReports.firstIndex(where: {
            $0.faction == faction && $0.gold == assault.gold && $0.violent
        }) {
            pendingReports.remove(at: open)
        }
    }

    /// The crime faction `key` polices as a guard, or nil.
    func policedFaction(of key: ReferenceKey) -> ReferenceKey? {
        world.policedFaction(of: key, guardFaction: reporter?.runtime.factions.guardFactionKey)
    }
}

extension CrimeSessionWorld {
    /// The crime faction `key` polices as a guard, or nil.
    func policedFaction(of key: ReferenceKey, guardFaction: ReferenceKey?) -> ReferenceKey? {
        guard let guardFaction, let profile = socialProfile(of: key) else { return nil }
        return GuardRecognition.policedFaction(of: profile, guardFaction: guardFaction)
    }
}

extension CrimeCoordinator {
    /// The journal's crime stats (<https://ck.uesp.net/wiki/QueryStat_-_Game>). The
    /// container menu counts pickpockets itself.
    func count(_ event: CrimeEvent) {
        guard event.perpetrator == .player else { return }
        switch event.kind {
        case .theft where event.stolenCount > 0:
            pendingCommands.append(event.isHorseTheft
                ? .incrementStat("Horses Stolen", by: 1)
                : .incrementStat("Items Stolen", by: event.stolenCount))
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
    }
}
