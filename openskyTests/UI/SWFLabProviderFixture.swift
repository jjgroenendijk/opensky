// Shared test double for the Developer > UI Lab SWF seam. Both hosted sections
// (the M8.2.5 movie selector and the M8.3.3 runtime driver) talk to the engine
// only through `SWFLabControlProviding`, so one recording fake covers the whole
// control surface without a renderer, a Metal device, or a game install.

@testable import opensky

@MainActor
final class FakeSWFLabProvider: SWFLabControlProviding {
    var swfMoviePaths: [String] = []
    var swfLayerEnabled = true
    var selections: [String?] = []
    var snapshot = SWFLabControlSnapshot(
        selectedPath: nil,
        layerEnabled: true,
        loadError: nil,
        tally: nil,
        unresolvedFontNames: [],
        drawStats: SWFDrawStats(),
        installLoaded: false,
        runtime: nil
    )

    func selectSWFMovie(path: String?) {
        selections.append(path)
    }

    var swfLabSnapshot: SWFLabControlSnapshot {
        snapshot
    }

    // MARK: Runtime calls, in the order the panel made them

    var startCount = 0
    var stopCount = 0
    var clearLogCount = 0
    var advanceTicks: [Int] = []
    var inputEvents: [SWFInputEvent] = []
    var calledMovieNames: [String] = []

    func startSWFRuntime() {
        startCount += 1
    }

    func advanceSWFRuntime(ticks: Int) {
        advanceTicks.append(ticks)
    }

    func stopSWFRuntime() {
        stopCount += 1
    }

    func sendSWFRuntimeInput(_ event: SWFInputEvent) {
        inputEvents.append(event)
    }

    func callSWFRuntimeMovie(_ name: String) {
        calledMovieNames.append(name)
    }

    func clearSWFInvokeLog() {
        clearLogCount += 1
    }

    /// Replaces the snapshot's runtime half, keeping the static half as it is.
    func setRuntime(_ runtime: SWFLabRuntimeSnapshot?) {
        snapshot = SWFLabControlSnapshot(
            selectedPath: snapshot.selectedPath,
            layerEnabled: snapshot.layerEnabled,
            loadError: snapshot.loadError,
            tally: snapshot.tally,
            unresolvedFontNames: snapshot.unresolvedFontNames,
            drawStats: snapshot.drawStats,
            installLoaded: snapshot.installLoaded,
            runtime: runtime
        )
    }
}
