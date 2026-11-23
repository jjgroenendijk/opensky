// Who saw a crime: the pairs `PerceptionRuntime` has already converged to
// `.detected`, so detection is not recomputed. A protocol, so crime tests run
// without a perception pass. An animal is a witness the criminal must kill, but it has
// no crime faction, so it raises no alarm and adds no bounty.
// See docs/engine/crime-reports.md#witnesses and docs/engine/detection.md.

import Foundation
public import OpenSkyFormatsESM
public import OpenSkyPerceptionInterface

/// Where the crime runtime asks whether anybody is watching.
@MainActor
public protocol CrimeWitnessSource {
    /// Actors that detect `perpetrator` right now, in a deterministic order.
    ///
    /// Detection only — an observer that is merely suspicious has not seen a
    /// crime, and crediting a bounty on a suspicion would make sneaking pay off
    /// at random.
    func witnesses(of perpetrator: ReferenceKey) -> [ReferenceKey]

    /// Whether `witness` raises an alarm, so its sight adds a bounty.
    func raisesAlarm(_ witness: ReferenceKey) -> Bool
}

extension CrimeWitnessSource {
    public func raisesAlarm(_: ReferenceKey) -> Bool {
        true
    }

    /// Whether a witness that raises an alarm is watching, which is all a bounty needs.
    public func isWitnessed(_ perpetrator: ReferenceKey) -> Bool {
        witnesses(of: perpetrator).contains { raisesAlarm($0) }
    }
}

/// Nobody is watching, which is what a synthetic scene and a headless runtime
/// answer.
///
/// Deliberately the *unwitnessed* answer rather than a witnessed one: a session
/// with no perception pass must not accrue bounty it cannot justify, and an
/// unwitnessed theft still marks the item stolen, so nothing is silently lost.
@MainActor
public struct NoCrimeWitnesses: CrimeWitnessSource {
    public func witnesses(of perpetrator: ReferenceKey) -> [ReferenceKey] {
        []
    }

    public init() {}
}

/// A fixed set of watchers, for tests and for a caller that resolved witnesses
/// some other way.
@MainActor
public struct FixedCrimeWitnesses: CrimeWitnessSource {
    /// Watchers per perpetrator. An actor with no entry is unobserved.
    public var observers: [ReferenceKey: [ReferenceKey]]
    /// Watchers with no crime faction, such as animals.
    public var silent: Set<ReferenceKey> = []

    init(observers: [ReferenceKey: [ReferenceKey]] = [:]) {
        self.observers = observers
    }

    /// Everybody in `observers` watches `perpetrator`.
    init(watching perpetrator: ReferenceKey, by observers: [ReferenceKey]) {
        self.init(observers: [perpetrator: observers])
    }

    public func witnesses(of perpetrator: ReferenceKey) -> [ReferenceKey] {
        observers[perpetrator] ?? []
    }

    public func raisesAlarm(_ witness: ReferenceKey) -> Bool {
        !silent.contains(witness)
    }
}

/// The real seam: the perception pass, filtered to live observers. The session
/// supplies `isAlive`, because the runtime holds no actor values. Without it every
/// detected observer counts.
@MainActor
public struct PerceptionCrimeWitnesses: CrimeWitnessSource {
    /// The pass whose converged pairs are read. Weak because the controller
    /// that owns the crime runtime owns this too.
    public weak var perception: (any DetectionObserving)?
    /// Whether one observer is still alive to report. Nil accepts everybody.
    public var isAlive: ((ReferenceKey) -> Bool)?
    /// Whether one observer has a crime faction to raise an alarm with. Nil: everybody has.
    public var hasCrimeFaction: ((ReferenceKey) -> Bool)?

    public init(
        perception: (any DetectionObserving)?,
        isAlive: ((ReferenceKey) -> Bool)? = nil,
        hasCrimeFaction: ((ReferenceKey) -> Bool)? = nil
    ) {
        self.perception = perception
        self.isAlive = isAlive
        self.hasCrimeFaction = hasCrimeFaction
    }

    public func raisesAlarm(_ witness: ReferenceKey) -> Bool {
        hasCrimeFaction?(witness) ?? true
    }

    public func witnesses(of perpetrator: ReferenceKey) -> [ReferenceKey] {
        guard let perception else { return [] }
        return perception.observersWitnessing(perpetrator).filter { isAlive?($0) ?? true }
    }
}
