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
    /// Who is a victim, a trespasser, alarmed, or arresting. Nil without a crime runtime.
    public var situation: CrimeSituation?

    public static let empty = CrimeConditionResolution()

    public init(
        factions: FactionStore? = nil,
        sourcePlugin: String? = nil,
        currentCrimeFaction: ReferenceKey? = nil,
        ledgers: [ReferenceKey: CrimeLedgerState] = [:],
        situation: CrimeSituation? = nil
    ) {
        facts = ActorConditionFacts(store: factions, sourcePlugin: sourcePlugin, facts: ledgers)
        self.currentCrimeFaction = currentCrimeFaction
        self.situation = situation
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

/// The live crime encounter as conditions read it. Every fight here is with the player.
nonisolated public struct CrimeSituation: Equatable, Sendable {
    /// The `GuardFaction` default object, or nil when the load order has none.
    public var guardFaction: ReferenceKey?
    /// Actors the player assaulted or murdered.
    public var victims: Set<ReferenceKey>
    /// Actors standing in a cell whose owner they may not use.
    public var trespassers: Set<ReferenceKey>
    /// Guards that pursue or confront the player.
    public var alarmed: Set<ReferenceKey>
    /// The guard holding the arrest talk with the player.
    public var arrestingGuard: ReferenceKey?
    /// Crime factions whose bounty the player has the gold to pay now.
    public var payableFactions: Set<ReferenceKey>
    /// Days the player served in the last jail sentence.
    public var lastSentenceDays: Int
    /// Who owns each reference a run-on can name.
    public var owners: [ReferenceKey: ReferenceOwner]
    /// The warnings each guard gave a trespasser, for `GetTrespassWarningLevel`.
    public var trespassWarnings: [ReferenceKey: Int] = [:]

    public init(
        guardFaction: ReferenceKey? = nil,
        victims: Set<ReferenceKey> = [],
        trespassers: Set<ReferenceKey> = [],
        alarmed: Set<ReferenceKey> = [],
        arrestingGuard: ReferenceKey? = nil,
        payableFactions: Set<ReferenceKey> = [],
        lastSentenceDays: Int = 0,
        owners: [ReferenceKey: ReferenceOwner] = [:]
    ) {
        self.guardFaction = guardFaction
        self.victims = victims
        self.trespassers = trespassers
        self.alarmed = alarmed
        self.arrestingGuard = arrestingGuard
        self.payableFactions = payableFactions
        self.lastSentenceDays = lastSentenceDays
        self.owners = owners
    }
}

nonisolated extension ConditionContext {
    /// Empty when no crime runtime is wired, so `GetCrimeGold` is a
    /// reason-tagged false rather than an actor who owes nothing.
    public var crime: CrimeConditionResolution {
        get { self[resolution: CrimeConditionResolution.self] }
        set { self[resolution: CrimeConditionResolution.self] = newValue }
    }
}
