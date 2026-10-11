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

    /// Plays the entry idle the `ActionActivate` tree picks while `actor` gets ready to
    /// sit, then marks it seated.
    @discardableResult
    public func enterFurniture(_ actor: ReferenceKey, use: FurnitureUse) -> IdleReport? {
        guard let store, let now = world?.idleAnimationTime else { return nil }
        var entering = use
        entering.sitState = .readyToSit
        furnitureUses[actor] = entering
        let roots = store.roots(underAction: Self.furnitureEntryAction)
        let selection = selector(for: actor).select(roots: roots)
        entering.sitState = .sitting
        furnitureUses[actor] = entering
        return play(selection, on: actor, source: "furniture", now: now)
    }

    /// Stops the seat idle and forgets where the actor's graph was.
    public func leaveFurniture(_ actor: ReferenceKey) {
        guard furnitureUses.removeValue(forKey: actor) != nil else { return }
        endIdle(of: actor)
        sessions[actor]?.playing = nil
        sessions[actor]?.waiting = nil
    }

    public func furnitureUse(of actor: ReferenceKey) -> FurnitureUse? {
        furnitureUses[actor]
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
