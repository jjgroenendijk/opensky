// CellStreamCore decision logic (todo 3.2 async build): accounted-set makeup,
// diff application (request dedupe, unload forgetting), and build integration
// (void/failed no-retry, stale/out-of-order discard). Pure value type -- no
// Metal, no async, synthetic coordinates (AGENTS.md testing rule).

@testable import opensky
import Testing

struct CellStreamCoreTests {
    private func coordinate(_ x: Int32, _ y: Int32) -> CellCoordinate {
        CellCoordinate(x: x, y: y)
    }

    // MARK: - accountedCells

    @Test
    func accountedUnionsEverySet() {
        var core = CellStreamCore()
        _ = core.apply(diff: CellGridDiff(loads: [coordinate(0, 0)], unloads: []))
        _ = core.integrate(coordinate: coordinate(0, 0), kind: .success)
        _ = core.apply(diff: CellGridDiff(loads: [coordinate(1, 0)], unloads: []))
        _ = core.integrate(coordinate: coordinate(1, 0), kind: .void)
        _ = core.apply(diff: CellGridDiff(loads: [coordinate(2, 0)], unloads: []))
        _ = core.integrate(coordinate: coordinate(2, 0), kind: .failure)
        _ = core.apply(diff: CellGridDiff(loads: [coordinate(3, 0)], unloads: []))

        // resident + void + failed + in-flight all count as accounted.
        #expect(core.accountedCells == [
            coordinate(0, 0), coordinate(1, 0), coordinate(2, 0), coordinate(3, 0)
        ])
    }

    // MARK: - apply

    @Test
    func loadsBecomeRequestsAndInFlight() {
        var core = CellStreamCore()
        let actions = core.apply(diff: CellGridDiff(
            loads: [coordinate(0, 0), coordinate(1, 0)], unloads: []
        ))
        #expect(Set(actions.requests) == [coordinate(0, 0), coordinate(1, 0)])
        #expect(actions.removals.isEmpty)
        #expect(core.inFlight == [coordinate(0, 0), coordinate(1, 0)])
    }

    @Test
    func voidAndFailedSlotsStayAccountedSoTheyAreNeverReRequested() {
        var core = CellStreamCore()
        _ = core.apply(diff: CellGridDiff(loads: [coordinate(0, 0), coordinate(1, 0)], unloads: []))
        _ = core.integrate(coordinate: coordinate(0, 0), kind: .void)
        _ = core.integrate(coordinate: coordinate(1, 0), kind: .failure)
        // Both terminal, neither in-flight -- accounted keeps the grid from
        // asking for them again.
        #expect(core.inFlightCountIsZero)
        #expect(core.accountedCells == [coordinate(0, 0), coordinate(1, 0)])
    }

    @Test
    func unloadDropsResidentAndForgetsVoidFailedInFlight() {
        var core = CellStreamCore()
        _ = core.apply(diff: CellGridDiff(
            loads: [coordinate(0, 0), coordinate(1, 0), coordinate(2, 0), coordinate(3, 0)],
            unloads: []
        ))
        _ = core.integrate(coordinate: coordinate(0, 0), kind: .success)
        _ = core.integrate(coordinate: coordinate(1, 0), kind: .void)
        _ = core.integrate(coordinate: coordinate(2, 0), kind: .failure)
        // coordinate(3,0) stays in-flight.

        let actions = core.apply(diff: CellGridDiff(loads: [], unloads: [
            coordinate(0, 0), coordinate(1, 0), coordinate(2, 0), coordinate(3, 0)
        ]))
        // Only the resident cell needs a composition removal.
        #expect(actions.removals == [coordinate(0, 0)])
        // Every set forgot the slot -> a return visit rebuilds fresh.
        #expect(core.accountedCells.isEmpty)
    }

    // MARK: - integrate

    @Test
    func integratingSuccessMakesResident() {
        var core = CellStreamCore()
        _ = core.apply(diff: CellGridDiff(loads: [coordinate(0, 0)], unloads: []))
        let result = core.integrate(coordinate: coordinate(0, 0), kind: .success)
        #expect(result == .integrated)
        #expect(core.resident == [coordinate(0, 0)])
    }

    @Test
    func completionForUnloadedCellIsDiscardedStale() {
        var core = CellStreamCore()
        _ = core.apply(diff: CellGridDiff(loads: [coordinate(0, 0)], unloads: []))
        // Cell leaves the grid before its build lands.
        _ = core.apply(diff: CellGridDiff(loads: [], unloads: [coordinate(0, 0)]))
        let result = core.integrate(coordinate: coordinate(0, 0), kind: .success)
        #expect(result == .discardedStale)
        #expect(core.resident.isEmpty)
        #expect(core.accountedCells.isEmpty)
    }

    @Test
    func duplicateLateCompletionIsDiscardedStale() {
        var core = CellStreamCore()
        _ = core.apply(diff: CellGridDiff(loads: [coordinate(0, 0)], unloads: []))
        #expect(core.integrate(coordinate: coordinate(0, 0), kind: .success) == .integrated)
        // A second completion for the same slot (re-dispatch race) finds it no
        // longer in-flight -> ignored, no double-integrate.
        #expect(core.integrate(coordinate: coordinate(0, 0), kind: .success) == .discardedStale)
        #expect(core.resident == [coordinate(0, 0)])
    }

    @Test
    func outOfOrderCompletionsAllIntegrate() {
        var core = CellStreamCore()
        let cells = [coordinate(0, 0), coordinate(1, 0), coordinate(2, 0)]
        _ = core.apply(diff: CellGridDiff(loads: Set(cells), unloads: []))
        // Integrate in reverse dispatch order -- each is still in-flight, so
        // completion order does not matter.
        #expect(core.integrate(coordinate: cells[2], kind: .success) == .integrated)
        #expect(core.integrate(coordinate: cells[0], kind: .success) == .integrated)
        #expect(core.integrate(coordinate: cells[1], kind: .success) == .integrated)
        #expect(core.resident == Set(cells))
    }

    // MARK: - World-state rebuilds (issue #160)

    @Test
    func aRebuildKeepsTheCellResidentWhileItIsInFlight() {
        var core = CellStreamCore()
        let cell = coordinate(0, 0)
        _ = core.apply(diff: CellGridDiff(loads: [cell], unloads: []))
        _ = core.integrate(coordinate: cell, kind: .success)

        let accepted = core.beginRebuild(cell)
        #expect(accepted)
        #expect(core.resident == [cell])
        #expect(core.rebuilding == [cell])
        #expect(core.inFlight.isEmpty)
    }

    @Test
    func aRebuildCompletionIntegratesInsteadOfBeingDiscardedAsStale() {
        var core = CellStreamCore()
        let cell = coordinate(0, 0)
        _ = core.apply(diff: CellGridDiff(loads: [cell], unloads: []))
        _ = core.integrate(coordinate: cell, kind: .success)
        _ = core.beginRebuild(cell)

        #expect(core.integrate(coordinate: cell, kind: .success) == .integrated)
        #expect(core.resident == [cell])
        #expect(core.rebuilding.isEmpty)
        // A further completion has nothing to replace -> stale again.
        #expect(core.integrate(coordinate: cell, kind: .success) == .discardedStale)
    }

    @Test
    func aFailedRebuildLeavesTheOldSceneResident() {
        var core = CellStreamCore()
        let cell = coordinate(0, 0)
        _ = core.apply(diff: CellGridDiff(loads: [cell], unloads: []))
        _ = core.integrate(coordinate: cell, kind: .success)
        _ = core.beginRebuild(cell)

        #expect(core.integrate(coordinate: cell, kind: .failure) == .discardedStale)
        #expect(core.resident == [cell])
        #expect(core.failed.isEmpty)
        #expect(core.rebuilding.isEmpty)
    }

    @Test
    func aRebuildIsRefusedForACellThatIsNotResident() {
        var core = CellStreamCore()
        let cell = coordinate(0, 0)
        _ = core.apply(diff: CellGridDiff(loads: [cell], unloads: []))

        let accepted = core.beginRebuild(cell)
        #expect(!accepted)
        #expect(core.rebuilding.isEmpty)
    }

    @Test
    func unloadingACellForgetsItsRebuild() {
        var core = CellStreamCore()
        let cell = coordinate(0, 0)
        _ = core.apply(diff: CellGridDiff(loads: [cell], unloads: []))
        _ = core.integrate(coordinate: cell, kind: .success)
        _ = core.beginRebuild(cell)

        _ = core.apply(diff: CellGridDiff(loads: [], unloads: [cell]))
        #expect(core.rebuilding.isEmpty)
        #expect(core.resident.isEmpty)
        // The late rebuild completion now has nowhere to land.
        #expect(core.integrate(coordinate: cell, kind: .success) == .discardedStale)
    }
}

extension CellStreamCore {
    fileprivate var inFlightCountIsZero: Bool {
        inFlight.isEmpty
    }
}
