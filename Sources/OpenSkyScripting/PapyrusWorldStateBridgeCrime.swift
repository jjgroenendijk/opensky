// The crime half of `PapyrusWorldStateBridge`. Every operation goes through the
// session's `CrimeReporter`, the same path a witnessed theft takes. Without a
// reporter every native refuses.

import Foundation
import OpenSkyCrimeInterface
import OpenSkyFormatsESM

extension PapyrusWorldStateBridge {
    public func crimeGold(of faction: ReferenceKey) -> Int? {
        guard let reporter = crimeReporter?() else { return nil }
        return Int(reporter.crimeGold(of: faction))
    }

    public func crimeGold(of faction: ReferenceKey, violent: Bool) -> Int? {
        guard let reporter = crimeReporter?() else { return nil }
        return Int(reporter.crimeGold(of: faction, violent: violent))
    }

    @discardableResult
    public func modifyCrimeGold(of faction: ReferenceKey, by amount: Int, violent: Bool) -> Int? {
        guard let reporter = crimeReporter?() else { return nil }
        return Int(reporter.modifyCrimeGold(
            by: Int32(clamping: amount), violent: violent, of: faction
        ))
    }

    @discardableResult
    public func setCrimeGold(of faction: ReferenceKey, to gold: Int, violent: Bool) -> Int? {
        guard let reporter = crimeReporter?() else { return nil }
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

    /// Both alarms are one operation with a different crime kind. They count as
    /// witnessed without asking perception, because the script asserts the witness
    /// saw it.
    private func alarm(
        _ kind: CrimeKind,
        witness: ReferenceKey,
        criminal: ReferenceKey
    ) -> Int? {
        guard let reporter = crimeReporter?(), let world = reporter.world else { return nil }
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
