// Who saw it (issue #504, roadmap item 21.5): the seam between the perception
// pass and the bounty ledger.
//
// "If you are caught doing an illegal action by a witness you will incur a
// bounty and they will report your crime to local guards ... Successfully
// sneaking while committing a crime will prevent you from being detected"
// (<https://en.uesp.net/wiki/Skyrim:Crime>). That is exactly the question
// `PerceptionRuntime` already answers every fixed step, so nothing here
// recomputes detection: it reads the pairs the pass has already converged and
// keeps the ones that reached `.detected`.
//
// A protocol rather than a direct dependency for the reason
// `CrimeHostilitySource` is one: the crime runtime has to be testable without a
// perception pass, a synthetic scene has no observers at all, and a session
// that runs the real pass hands over the adapter below.
//
// ## What this deliberately does not model
//
// Reporting. In the original a witness walks to a guard and tells them, which
// is a package, a travel path and a conversation; this engine credits the
// bounty the moment a live witness sees the act. Follower-committed crimes,
// animal witnesses and the child-tells-an-adult chain are the same
// simplification from the other side. All of it is recorded as a v1 limitation
// in docs/engine/crime.md rather than pretended away.
//
// Documented in docs/engine/crime.md and docs/engine/detection.md.

import Foundation

/// Where the crime runtime asks whether anybody is watching.
@MainActor
protocol CrimeWitnessSource {
    /// Actors that detect `perpetrator` right now, in a deterministic order.
    ///
    /// Detection only — an observer that is merely suspicious has not seen a
    /// crime, and crediting a bounty on a suspicion would make sneaking pay off
    /// at random.
    func witnesses(of perpetrator: ReferenceKey) -> [ReferenceKey]
}

extension CrimeWitnessSource {
    /// Whether anybody is watching, which is all a bounty decision needs.
    func isWitnessed(_ perpetrator: ReferenceKey) -> Bool {
        !witnesses(of: perpetrator).isEmpty
    }
}

/// Nobody is watching, which is what a synthetic scene and a headless runtime
/// answer.
///
/// Deliberately the *unwitnessed* answer rather than a witnessed one: a session
/// with no perception pass must not accrue bounty it cannot justify, and an
/// unwitnessed theft still marks the item stolen, so nothing is silently lost.
@MainActor
struct NoCrimeWitnesses: CrimeWitnessSource {
    func witnesses(of perpetrator: ReferenceKey) -> [ReferenceKey] {
        []
    }
}

/// A fixed set of watchers, for tests and for a caller that resolved witnesses
/// some other way.
@MainActor
struct FixedCrimeWitnesses: CrimeWitnessSource {
    /// Watchers per perpetrator. An actor with no entry is unobserved.
    var observers: [ReferenceKey: [ReferenceKey]]

    init(observers: [ReferenceKey: [ReferenceKey]] = [:]) {
        self.observers = observers
    }

    /// Everybody in `observers` watches `perpetrator`.
    init(watching perpetrator: ReferenceKey, by observers: [ReferenceKey]) {
        self.init(observers: [perpetrator: observers])
    }

    func witnesses(of perpetrator: ReferenceKey) -> [ReferenceKey] {
        observers[perpetrator] ?? []
    }
}

/// The real seam: the perception pass, filtered to live observers.
///
/// `isAlive` is supplied rather than read here because the runtime holds no
/// actor-value surface — the same reason `MeleeCombatWorld` asks the session
/// for a block multiplier instead of computing one. A session that cannot tell
/// the dead from the living passes nothing and every detected observer counts,
/// which is the pre-death behaviour rather than a new wrong answer.
@MainActor
struct PerceptionCrimeWitnesses: CrimeWitnessSource {
    /// The pass whose converged pairs are read. Weak because the controller
    /// that owns the crime runtime owns this too.
    weak var perception: PerceptionRuntime?
    /// Whether one observer is still alive to report. Nil accepts everybody.
    var isAlive: ((ReferenceKey) -> Bool)?

    init(
        perception: PerceptionRuntime?,
        isAlive: ((ReferenceKey) -> Bool)? = nil
    ) {
        self.perception = perception
        self.isAlive = isAlive
    }

    func witnesses(of perpetrator: ReferenceKey) -> [ReferenceKey] {
        guard let perception else { return [] }
        return perception.observersDetecting(perpetrator).filter { isAlive?($0) ?? true }
    }
}
