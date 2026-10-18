// Furniture entry idles and dependent animated objects. An actor that sits plays
// the idle the `ActionActivate` tree picks for its marker and holds it. A dependent
// takes its owner's idle events, as the chopping block's executioner and guard take
// the prisoner's. See docs/engine/idle-runtime.md.

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

extension IdleCoordinator {
    /// The tree the game picks a furniture entry idle from.
    static let furnitureEntryAction = "ActionActivate"

    /// How long an actor reads `GetSitting` 4 after it gets up. OpenSky plays no exit
    /// idle, so this stands in for one; a script that waits for the state sees it.
    static let standUpSeconds: Float = 1

    /// Plays the entry idle the `ActionActivate` tree picks while `actor` gets ready to
    /// sit, then marks it seated. An NPC whose sit idle still loads reads `GetSitting` 1
    /// until it plays; the player and a bed or lean never do (CK wiki "GetSitting").
    @discardableResult
    public func enterFurniture(_ actor: ReferenceKey, use: FurnitureUse) -> IdleReport? {
        guard let store, let now = world?.idleAnimationTime else { return nil }
        standingUntil[actor] = nil
        var entering = use
        entering.sitState = .readyToSit
        furnitureUses[actor] = entering
        let roots = store.roots(underAction: Self.furnitureEntryAction)
        let selection = selector(for: actor).select(roots: roots)
        let report = play(selection, on: actor, source: "furniture", now: now)
        let loads = report.failure == "loading" && actor != .player
            && use.animationType == Self.sitAnimationType
        entering.sitState = loads ? .loading : .sitting
        furnitureUses[actor] = entering
        return report
    }

    /// Stops the seat idle and forgets where the actor's graph was. The actor reads
    /// `GetSitting` 4 for `standUpSeconds`, then 0.
    public func leaveFurniture(_ actor: ReferenceKey) {
        guard furnitureUses[actor] != nil else { return }
        furnitureUses[actor]?.sitState = .readyToStand
        standingUntil[actor] = (world?.idleAnimationTime ?? 0) + Self.standUpSeconds
        endIdle(of: actor)
        sessions[actor]?.playing = nil
        sessions[actor]?.waiting = nil
    }

    /// Who sits where, for every condition context: `GetSitting` in a quest, a topic, or
    /// `Actor.GetSitState`, not only in the idle trees.
    public var furnitureResolution: FurnitureConditionResolution {
        FurnitureConditionResolution(uses: furnitureUses, isAvailable: true)
    }

    /// xEdit's furniture animation enum: 1 sit.
    static let sitAnimationType: UInt32 = 1

    /// A loading sit becomes seated once its idle plays; a stand-up ends on time.
    func advanceSitStates(now: Float) {
        for (actor, use) in furnitureUses where use.sitState == .loading {
            if sessions[actor]?.playing != nil {
                furnitureUses[actor]?.sitState = .sitting
            }
        }
        // A clock that went back, such as after a load, also ends the stand-up.
        for (actor, until) in standingUntil
            where now >= until || now < until - Self.standUpSeconds
        {
            standingUntil[actor] = nil
            if furnitureUses[actor]?.sitState == .readyToStand {
                furnitureUses[actor] = nil
            }
        }
    }

    public func addDependent(_ dependent: ReferenceKey, of owner: ReferenceKey) {
        guard dependent != owner, dependents[owner]?.contains(dependent) != true else { return }
        dependents[owner, default: []].append(dependent)
    }

    public func removeDependent(_ dependent: ReferenceKey, of owner: ReferenceKey) {
        dependents[owner]?.removeAll { $0 == dependent }
        if dependents[owner]?.isEmpty == true {
            dependents[owner] = nil
        }
    }

    /// The owner and every dependent below it, each once, owner first.
    func withDependents(_ owner: ReferenceKey) -> [ReferenceKey] {
        var order: [ReferenceKey] = []
        var pending = [owner]
        while let next = pending.first {
            pending.removeFirst()
            guard !order.contains(next) else { continue }
            order.append(next)
            pending += dependents[next] ?? []
        }
        return order
    }
}
