// The event queue one behavior graph instance owns (issue #187).
//
// `hkbBehaviorGraphData` declares events positionally, the same way it declares
// variables: index i has flags `m_eventInfos[i]` and name
// `m_stringData.m_eventNames[i]`. Nodes raise and test events by index; the
// engine outside the graph raises them by name.
//
// Ordering is the whole point of this type, because it is what makes an update
// deterministic. An event raised during an update is *not* visible to the rest
// of that same update: it lands in the next update's queue. That is one
// documented decision rather than an emergent property of traversal order, and
// it means two instances stepped with the same inputs fire the same events in
// the same order whatever the tree shape is. See the update-order section of
// docs/engine/behavior-runtime.md.

import Foundation

/// One raised event: which index, what it is called, and the string payload
/// the authored data attached to it, if any.
nonisolated struct BehaviorEvent: Equatable, Sendable {
    let id: Int
    let name: String?
    let payload: String?

    init(id: Int, name: String? = nil, payload: String? = nil) {
        self.id = id
        self.name = name
        self.payload = payload
    }
}

/// The two-phase event queue of one instance. `pending` holds what the next
/// update will see; `active` holds what the update in progress may test.
nonisolated struct BehaviorEventQueue: Equatable {
    /// Declared name per event index; nil where the graph declares none.
    let names: [String?]
    /// Name -> index. First declaration wins, as in `BehaviorVariableStore`.
    private let indexByName: [String: Int]

    /// Raised but not yet promoted into an update.
    private(set) var pending: [BehaviorEvent] = []
    /// Visible to the update in progress, in raise order.
    private(set) var active: [BehaviorEvent] = []

    /// Cap on `pending`, so a modifier that raises an event every update
    /// without anything consuming it cannot grow the queue without bound. The
    /// oldest entries are dropped, because the newest state is the useful one.
    static let capacity = 256

    init(data: HKBBehaviorGraphData?) {
        let declared = data?.stringData?.eventNames ?? []
        let count = max(declared.count, data?.eventFlags.count ?? 0)
        var names = [String?](repeating: nil, count: count)
        for (index, name) in declared.enumerated() where index < count {
            names[index] = name
        }
        self.names = names
        var byName: [String: Int] = [:]
        for (index, name) in names.enumerated() {
            guard let name, byName[name] == nil else { continue }
            byName[name] = index
        }
        indexByName = byName
    }

    var count: Int {
        names.count
    }

    func index(of name: String) -> Int? {
        indexByName[name]
    }

    func name(at index: Int) -> String? {
        names.indices.contains(index) ? names[index] : nil
    }

    // MARK: - Raising

    /// Queues the event at `id` for the next update. An id outside the declared
    /// range is dropped: Havok spells "no event" as -1, and a modded graph
    /// naming an index this graph does not declare has nothing to raise.
    mutating func raise(id: Int, payload: String? = nil) {
        guard names.indices.contains(id) else { return }
        pending.append(BehaviorEvent(id: id, name: names[id], payload: payload))
        if pending.count > Self.capacity {
            pending.removeFirst(pending.count - Self.capacity)
        }
    }

    /// Queues the event called `name`. Returns false when the graph declares no
    /// such event, so a caller wiring engine state can report the miss.
    @discardableResult
    mutating func raise(named name: String, payload: String? = nil) -> Bool {
        guard let id = index(of: name) else { return false }
        raise(id: id, payload: payload)
        return true
    }

    // MARK: - Update phases

    /// Promotes everything raised since the last update into the active set and
    /// clears the pending set. Returns the newly active events in raise order.
    @discardableResult
    mutating func beginUpdate() -> [BehaviorEvent] {
        active = pending
        pending = []
        return active
    }

    /// Ends the update, clearing what nodes could test this frame. Returns the
    /// events the update saw, which is the fired-event half of the output
    /// contract 14.4 through 14.6 consume.
    @discardableResult
    mutating func endUpdate() -> [BehaviorEvent] {
        let fired = active
        active = []
        return fired
    }

    /// True when `id` was raised before the update in progress began.
    func isActive(id: Int) -> Bool {
        guard id >= 0 else { return false }
        return active.contains { $0.id == id }
    }
}
