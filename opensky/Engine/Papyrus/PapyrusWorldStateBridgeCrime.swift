// `PapyrusWorldStateBridge`'s crime half (issue #504, roadmap item 21.5),
// beside the actor, quest and magic halves.
//
// Every operation goes through the session's `CrimeReporter`, which is the same
// door a witnessed theft comes through: a scripted bounty and a stolen ring
// therefore reach the ledger, the journal and the save by one path, and a
// script cannot produce a bounty the engine could not have produced itself.
//
// The reporter is reached through a closure for the reason `mutatePerks` is:
// the controller owns it and hands over a getter, so a session that never built
// one leaves every native here refusing rather than answering zero.

import Foundation

extension PapyrusWorldStateBridge {
    func crimeGold(of faction: ReferenceKey) -> Int? {
        guard let reporter = crimeReporter?() else { return nil }
        return Int(reporter.runtime.crimeGold(of: faction))
    }

    @discardableResult
    func modifyCrimeGold(of faction: ReferenceKey, by amount: Int) -> Int? {
        guard let reporter = crimeReporter?() else { return nil }
        return Int(reporter.runtime.modifyCrimeGold(
            by: Int32(clamping: amount), of: faction
        ))
    }

    @discardableResult
    func setCrimeGold(of faction: ReferenceKey, to gold: Int) -> Int? {
        guard let reporter = crimeReporter?() else { return nil }
        return Int(reporter.runtime.setCrimeGold(Int32(clamping: gold), of: faction))
    }

    @discardableResult
    func sendAssaultAlarm(witness: ReferenceKey, criminal: ReferenceKey) -> Int? {
        alarm(.assault, witness: witness, criminal: criminal)
    }

    @discardableResult
    func sendTrespassAlarm(witness: ReferenceKey, criminal: ReferenceKey) -> Int? {
        alarm(.trespass, witness: witness, criminal: criminal)
    }

    /// Both alarms are the same operation with a different crime kind: the
    /// witness is the victim and the place it stands in decides the faction.
    ///
    /// Reported as witnessed outright rather than run past the perception pass.
    /// The script is asserting that this actor caught the criminal — that is
    /// what "have this actor pretend he caught the specified criminal" means —
    /// so asking the detection state whether it really did would let a scripted
    /// alarm fail silently because the witness happened to be facing away.
    private func alarm(
        _ kind: CrimeKind,
        witness: ReferenceKey,
        criminal: ReferenceKey
    ) -> Int? {
        guard let reporter = crimeReporter?(), let world = reporter.world else { return nil }
        let cell = world.crimeCell(of: witness)
        return Int(reporter.runtime.report(CrimeEvent(
            kind: kind,
            perpetrator: criminal,
            victim: witness,
            crimeFaction: world.crimeFaction(in: cell),
            cell: cell,
            witnessed: true
        )).gold)
    }
}
