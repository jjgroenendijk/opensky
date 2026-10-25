// Cell reset: a cell the player left long enough ago returns to its plugin state when
// the player enters it again (CK wiki "Cell Reset"). See docs/engine/cell-reset.md.

import OpenSkyActorsInterface
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyWorldState

/// One reset, for the runtime state readout.
nonisolated public struct CellResetRecord: Equatable, Sendable {
    public let location: CellSceneLocation
    public let resetReferences: [ReferenceKey]
}

/// The record questions a reset asks, answered from the load-order stores.
public struct CellResetQueries {
    /// Whether the reference may return to its plugin state, such as a respawning
    /// actor or container. A No Respawn reference never reaches this test.
    public var respawns: (RuntimeReferenceEntry) -> Bool = { _ in true }
    /// Whether the cell's location is cleared, which waits `clearedHours`.
    public var isCleared: (CellScene) -> Bool = { _ in false }
    /// The cell's encounter zone has its "never resets" flag.
    public var neverResets: (CellScene) -> Bool = { _ in false }

    public init() {}
}

@MainActor
public final class CellResetCoordinator {
    /// What resets. Enable state, created references, quest and script state do not.
    public static let resetKinds: [WorldStateComponentKind] = [
        .death, .actorValues, .combat, .inventory, .activation, .lock, .deletion, .transform,
        .relocation, .harvest, .itemCopies, .leveledRoll
    ]

    public let store: WorldStateStore
    public let settings: CellResetSettings
    public let queries: CellResetQueries
    public let clock: () -> GameClock?
    public private(set) var lastReset: CellResetRecord?

    public init(
        store: WorldStateStore, settings: CellResetSettings = .vanilla,
        queries: CellResetQueries = CellResetQueries(),
        clock: @escaping () -> GameClock?
    ) {
        self.store = store
        self.settings = settings
        self.queries = queries
        self.clock = clock
    }

    private var now: Double? {
        clock().map { $0.totalGameSeconds / GameClock.secondsPerHour }
    }

    public var ledger: CellResetLedger {
        store.component(CellResetLedger.self, for: .player) ?? CellResetLedger()
    }

    /// A departure this far back marks a cell a script flagged for reset.
    static let forcedDeparture = -Double.infinity

    /// Papyrus `Cell.Reset`: the cell resets on its next load, even in a zone that never
    /// resets (<https://ck.uesp.net/wiki/Reset_-_Cell>).
    public func flagForReset(_ location: CellSceneLocation) {
        var ledger = ledger
        ledger.departures[location] = Self.forcedDeparture
        store.set(ledger, for: .player)
    }

    public func cellDetached(_ location: CellSceneLocation) {
        guard let now, ledger.departures[location] != Self.forcedDeparture else { return }
        var ledger = ledger
        ledger.departures[location] = now
        store.set(ledger, for: .player)
    }

    /// Resets `scene` when it is due and returns the references it reset.
    @discardableResult
    public func cellAttached(_ scene: CellScene) -> [ReferenceKey] {
        guard
            let location = scene.location, let now,
            let departure = ledger.departures[location]
        else { return [] }
        var ledger = ledger
        ledger.departures[location] = nil
        store.set(ledger, for: .player)
        let forced = departure == Self.forcedDeparture
        guard
            forced || !queries.neverResets(scene),
            forced || settings.isDue(
                departedAt: departure,
                now: now,
                cleared: queries.isCleared(scene)
            )
        else { return [] }
        let reset = scene.references.sortedEntries().filter(reset)
        lastReset = CellResetRecord(location: location, resetReferences: reset.map(\.key))
        return reset.map(\.key)
    }

    /// Moves every departure back far enough that each cell resets on the next visit.
    @discardableResult
    public func makeAllDue() -> Int {
        var ledger = ledger
        let wait = Double(max(settings.hours, settings.clearedHours))
        for (location, departure) in ledger.departures {
            ledger.departures[location] = departure - wait
        }
        store.set(ledger, for: .player)
        return ledger.departures.count
    }

    /// For a forced reset.
    public var readout: String {
        let waiting = "Cells left behind: \(ledger.departures.count)"
        guard let lastReset else { return waiting + "  Last cell reset: none" }
        return waiting + "  Last cell reset: \(lastReset.location)"
            + " (\(lastReset.resetReferences.count) references)"
    }

    private func reset(_ entry: RuntimeReferenceEntry) -> Bool {
        guard
            let delta = store.delta(for: entry.key), delta[.spawn] == nil,
            entry.placedReference?.isNoRespawn != true, entry.placedActor?.isNoRespawn != true,
            queries.respawns(entry)
        else { return false }
        var changed = false
        for kind in Self.resetKinds where store.reset(kind, for: entry.key) {
            changed = true
        }
        return changed
    }
}
