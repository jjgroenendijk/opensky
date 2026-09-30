// Crime ledgers per actor for `GetCrimeGold` and its two halves. See
// docs/engine/crime.md and docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// Every actor's crime ledger plus the FACT store a faction parameter resolves
/// against.
nonisolated public struct CrimeConditionResolution: Sendable {
    public let facts: ActorConditionFacts<FactionStore, CrimeLedgerState>
    /// What a null `ptFactionNull` parameter means: the hold the subject stands
    /// in. The context carries no cell, so the caller resolves it.
    public let currentCrimeFaction: ReferenceKey?

    public static let empty = CrimeConditionResolution()

    public init(
        factions: FactionStore? = nil,
        sourcePlugin: String? = nil,
        currentCrimeFaction: ReferenceKey? = nil,
        ledgers: [ReferenceKey: CrimeLedgerState] = [:]
    ) {
        facts = ActorConditionFacts(store: factions, sourcePlugin: sourcePlugin, facts: ledgers)
        self.currentCrimeFaction = currentCrimeFaction
    }

    public func key(of formID: FormID) -> ReferenceKey? {
        formID.isNull ? currentCrimeFaction : facts.key(of: formID)
    }

    /// Nil when no crime data is wired. An actor with no ledger owes nothing:
    /// every actor starts there.
    public func crimeGold(of faction: ReferenceKey, on actor: ReferenceKey) -> Int32? {
        guard facts.isAvailable else { return nil }
        return facts.fact(of: actor)?.gold(for: faction) ?? 0
    }

    /// One half of the debt, for `GetCrimeGoldViolent` and `GetCrimeGoldNonviolent`.
    public func crimeGold(
        of faction: ReferenceKey,
        violent: Bool,
        on actor: ReferenceKey
    ) -> Int32? {
        guard facts.isAvailable else { return nil }
        return facts.fact(of: actor)?.gold(for: faction, violent: violent) ?? 0
    }
}

nonisolated extension CrimeConditionResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    /// Empty when no crime runtime is wired, so `GetCrimeGold` is a
    /// reason-tagged false rather than an actor who owes nothing.
    public var crime: CrimeConditionResolution {
        get { self[resolution: CrimeConditionResolution.self] }
        set { self[resolution: CrimeConditionResolution.self] = newValue }
    }
}
