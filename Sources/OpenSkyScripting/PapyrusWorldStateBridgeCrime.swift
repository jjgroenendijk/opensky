// The crime half of `PapyrusWorldStateBridge`. Every operation goes through the
// session's `CrimeReporter`, the same path a witnessed theft takes. Without a
// reporter every native refuses.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM

extension PapyrusWorldStateBridge {
    public func crimeGold(of faction: ReferenceKey) -> Int? {
        guard let reporter = crimeNatives.crimeReporter?() else { return nil }
        return Int(reporter.crimeGold(of: faction))
    }

    public func crimeGold(of faction: ReferenceKey, violent: Bool) -> Int? {
        guard let reporter = crimeNatives.crimeReporter?() else { return nil }
        return Int(reporter.crimeGold(of: faction, violent: violent))
    }

    @discardableResult
    public func modifyCrimeGold(of faction: ReferenceKey, by amount: Int, violent: Bool) -> Int? {
        guard let reporter = crimeNatives.crimeReporter?() else { return nil }
        return Int(reporter.modifyCrimeGold(
            by: Int32(clamping: amount), violent: violent, of: faction
        ))
    }

    @discardableResult
    public func setCrimeGold(of faction: ReferenceKey, to gold: Int, violent: Bool) -> Int? {
        guard let reporter = crimeNatives.crimeReporter?() else { return nil }
        return Int(reporter.setCrimeGold(
            Int32(clamping: gold), violent: violent, of: faction
        ))
    }

    @discardableResult
    public func sendAssaultAlarm(witness: ReferenceKey, criminal: ReferenceKey) -> Int? {
        alarm(.assault, witness: witness, criminal: criminal)
    }

    @discardableResult
    public func sendTrespassAlarm(witness: ReferenceKey, criminal: ReferenceKey) -> Int? {
        alarm(.trespass, witness: witness, criminal: criminal)
    }

    /// The first actor that detects the player calls the werewolf crime
    /// (<https://ck.uesp.net/wiki/SendWereWolfTransformation_-_Game>).
    /// - Returns: the bounty accrued, zero when nobody saw, or nil without a crime runtime.
    @discardableResult
    public func sendWerewolfTransformation() -> Int? {
        guard let reporter = crimeNatives.crimeReporter?() else { return nil }
        return Int(reporter.reportWerewolfTransformation(by: playerKey)?.gold ?? 0)
    }

    /// The thief taking `reference` as a witnessed theft. Zero when the thief may take it.
    @discardableResult
    public func sendStealAlarm(on reference: ReferenceKey, thief: ReferenceKey) -> Int? {
        guard
            let reporter = crimeNatives.crimeReporter?(),
            let world = reporter.world else { return nil }
        guard case let .forbidden(owner) = reporter.verdict(on: reference, by: thief) else {
            return 0
        }
        let cell = world.crimeCell(of: reference)
        return Int(reporter.report(CrimeEvent(
            kind: .theft, perpetrator: thief, victim: owner.key,
            crimeFaction: world.crimeFaction(in: cell), cell: cell, witnessed: true,
            stolenValue: baseObject(of: reference).map(world.crimeItemValue(of:)) ?? 0
        )).gold)
    }

    /// Both alarms are one operation with a different crime kind. They count as
    /// witnessed without asking perception, because the script asserts the witness
    /// saw it.
    private func alarm(
        _ kind: CrimeKind,
        witness: ReferenceKey,
        criminal: ReferenceKey
    ) -> Int? {
        guard
            let reporter = crimeNatives.crimeReporter?(),
            let world = reporter.world else { return nil }
        let cell = world.crimeCell(of: witness)
        return Int(reporter.report(CrimeEvent(
            kind: kind,
            perpetrator: criminal,
            victim: witness,
            crimeFaction: world.crimeFaction(in: cell),
            cell: cell,
            witnessed: true
        )).gold)
    }
}
