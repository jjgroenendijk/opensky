// IdleControlProviding and HeadAssemblyControlProviding part of the shared panel fake.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyWorld

/// One "Play idle" request a section sent.
struct FiredIdle {
    let idle: ResolvedFormID
    let actor: ReferenceKey
    let ignoringConditions: Bool
}

/// What the Idles and Head Assembly sections read, and what they asked for.
final class FakeIdleState {
    var snapshot = IdleControlSnapshot.unavailable
    var tree: [IdleTreeLine] = []
    var fired: [FiredIdle] = []
    var picked: [(marker: ReferenceKey, actor: ReferenceKey)] = []
    var head = HeadAssemblySnapshot(actor: nil, head: nil, requested: .baked)
    var headSources: [(ActorHeadSource, ReferenceKey)] = []
}

extension FakeWorldProviders {
    func idleSnapshot(for _: ReferenceKey?) -> IdleControlSnapshot {
        idleState.snapshot
    }

    func setUsesIdleMarkers(_ enabled: Bool) {
        let old = idleState.snapshot
        idleState.snapshot = IdleControlSnapshot(
            isAvailable: old.isAvailable, usesIdleMarkers: enabled, markers: old.markers,
            idlingActorCount: old.idlingActorCount, report: old.report
        )
    }

    func idleTree(below _: ResolvedFormID) -> [IdleTreeLine] {
        idleState.tree
    }

    @discardableResult
    func fireIdle(
        _ idle: ResolvedFormID, on actor: ReferenceKey, ignoringConditions: Bool
    ) -> IdleReport? {
        idleState.fired.append(FiredIdle(
            idle: idle, actor: actor, ignoringConditions: ignoringConditions
        ))
        return nil
    }

    @discardableResult
    func pickIdle(at marker: ReferenceKey, for actor: ReferenceKey) -> IdleReport? {
        idleState.picked.append((marker, actor))
        return nil
    }

    func headAssemblySnapshot(for _: ReferenceKey?) -> HeadAssemblySnapshot {
        idleState.head
    }

    func setHeadSource(_ source: ActorHeadSource, for actor: ReferenceKey) {
        idleState.headSources.append((source, actor))
        idleState.head = HeadAssemblySnapshot(
            actor: idleState.head.actor, head: idleState.head.head, requested: source
        )
    }
}
