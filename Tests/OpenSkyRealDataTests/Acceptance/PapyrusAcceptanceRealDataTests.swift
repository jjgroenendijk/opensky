// Env-gated Papyrus acceptance over the user's read-only vanilla PEX corpus.

import Foundation
@testable import OpenSkyFormatsPEX
@testable import OpenSkyGameData
@testable import OpenSkyScripting
@testable import OpenSkyScriptingInterface
import OpenSkyTagsTesting
@testable import OpenSkyWorldState
import Testing

@Suite(.tags(.acceptance))
@MainActor
struct PapyrusAcceptanceRealDataTests {
    private struct RunEvidence {
        let entryPoints: Int
        let terminalOutcomes: Int
        let completed: Int
        let pending: Int
        let tickSeconds: Double
    }

    private static let entryPointNames = [
        "OnInit", "OnLoad", "OnPlayerLoadGame"
    ]

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func closesHeadlessNativeAcceptance() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let loader = PexScriptLoader(fileSystem: VirtualFileSystem(root: root))
        let paths = loader.scriptPaths()
        let files = try paths.map(loader.load)
        let registry = PapyrusNativeRegistry.standard
        let census = PexNativeCensus(files: files)
        let coverage = census.coverage(in: registry)
        let (runtime, run) = try executeEntryPoints(files: files, registry: registry)

        #expect(paths.count == 14302)
        #expect(census.declarationTotal == 686)
        #expect(census.referenceTotal == 65477)
        #expect(census.distinctReferencedTotal == 508)
        // Pinned so a new native shows up here. The SKSE perk-point functions add
        // nothing, because the vanilla corpus never calls them. The six scene and
        // story natives are all called, and 8 of the 9 menu and map natives.
        #expect(coverage == PexNativeCoverage(implemented: 186, referenced: 508))
        #expect(run.entryPoints == 577)
        // 21 entry points still wait, or yield each tick in a loop with no wait, when
        // the tick cap ends the run. A yielding loop calls its natives every tick.
        #expect(run.pending == 21)
        #expect(run.terminalOutcomes == 556)
        #expect(run.completed == 556)
        // A call on `None` returns its default, and a failed cast gives `None`, so no
        // entry point faults.
        #expect(runtime.tally.faultTotal == 0)
        #expect(runtime.tally.nativeCallTotal == 814_881)
        #expect(runtime.tally.unimplementedNativeTotal == 160)
        // World natives refuse in this headless run, so their calls count as
        // failures rather than unimplemented natives.
        #expect(runtime.tally.nativeFailureTotal == 592_821)
        #expect(runtime.tally.deferredAnimationTotal == 236)
        #expect(runtime.tally.rankedFaultKinds.isEmpty)
        #expect(
            runtime.tally.rankedUnimplementedNatives.first?.name
                == "ReferenceAlias.AddInventoryEventFilter"
        )
        #expect(runtime.tally.rankedUnimplementedNatives.first?.count == 41)

        let report = Self.report(
            paths: paths,
            census: census,
            coverage: coverage,
            runtime: runtime,
            run: run
        )
        print(report)
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        try report.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func executeEntryPoints(
        files: [PexFile],
        registry: PapyrusNativeRegistry
    ) throws -> (PapyrusRuntime, RunEvidence) {
        var limits = PapyrusLimits.standard
        limits.instructionBudget = 10000
        limits.tallyNames = 1024
        let runtime = PapyrusRuntime(
            files: files,
            nativeDispatch: registry,
            limits: limits
        )
        let scheduler = PapyrusScheduler(
            runtime: runtime,
            fixedStepSeconds: GameClock.secondsPerDay
        )
        var clock = GameClock()
        _ = scheduler.tick(gameClock: clock)
        var entryPoints = 0

        for script in runtime.scripts.values.sorted(by: { $0.name < $1.name }) {
            let names = Self.entryPoints(in: script)
            guard !names.isEmpty else { continue }
            let handle = try runtime.makeInstance(scriptName: script.name)
            for name in names {
                entryPoints += 1
                scheduler.schedule(runtime.invoke(name, on: handle))
            }
        }

        var outcomes: [PapyrusRunOutcome] = []
        let started = ContinuousClock.now
        for _ in 0 ..< 256 {
            clock = GameClock(
                totalGameSeconds: clock.totalGameSeconds + GameClock.secondsPerDay
            )
            outcomes.append(contentsOf: scheduler.tick(gameClock: clock))
            if scheduler.pendingCount == 0 {
                break
            }
        }
        let elapsed = ContinuousClock.now - started
        let completed = outcomes.reduce(into: 0) { count, outcome in
            if case .completed = outcome {
                count += 1
            }
        }
        return (
            runtime,
            RunEvidence(
                entryPoints: entryPoints,
                terminalOutcomes: outcomes.count,
                completed: completed,
                pending: scheduler.pendingCount,
                tickSeconds: Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e18
            )
        )
    }

    private static func entryPoints(in script: PexObject) -> [String] {
        guard
            let state = script.states.first(where: {
                PapyrusRuntime.matches($0.name, "")
            })
        else { return [] }
        return entryPointNames.compactMap { expectedName in
            state.functions.first(where: {
                PapyrusRuntime.matches($0.name, expectedName)
                    && !$0.function.flags.contains(.native)
                    && $0.function.parameters.isEmpty
            })?.name
        }
    }

    /// Runs the same entry points and holds the interpreter to an instruction rate.
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot), .tags(.perf, .slow))
    func runsEntryPointsAtTheInstructionRate() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let loader = PexScriptLoader(fileSystem: VirtualFileSystem(root: root))
        let files = try loader.scriptPaths().map(loader.load)
        let (runtime, run) = try executeEntryPoints(
            files: files,
            registry: .standard
        )
        let rate = Self.instructionRate(runtime: runtime, run: run)
        print("Papyrus instructions per second\t\(Int(rate))")
        #expect(rate >= Self.minimumInstructionRate)
    }

    /// Instructions per second. Measured 1.8 million optimized and 1.7 million in Debug,
    /// which builds the scripting modules optimized too.
    private static var minimumInstructionRate: Double {
        #if OPENSKY_OPTIMIZED
            600_000
        #else
            500_000
        #endif
    }

    private static func instructionRate(runtime: PapyrusRuntime, run: RunEvidence) -> Double {
        Double(runtime.tally.instructionsExecuted) / max(run.tickSeconds, 0.001)
    }

    private static func report(
        paths: [String],
        census: PexNativeCensus,
        coverage: PexNativeCoverage,
        runtime: PapyrusRuntime,
        run: RunEvidence
    ) -> String {
        let unknown = runtime.tally.rankedUnimplementedNatives.prefix(100)
            .map { "\($0.count)\t\($0.name)" }
            .joined(separator: "\n")
        let faults = runtime.tally.rankedFaultKinds
            .map { "\($0.count)\t\($0.name)" }
            .joined(separator: "\n")
        return """
        Papyrus M11.1 acceptance, native coverage last re-measured 2026-08-08
        scripts decoded\t\(paths.count)
        native declarations\t\(census.declarationTotal)
        native references\t\(census.referenceTotal)
        distinct natives referenced\t\(coverage.referenced)
        distinct natives implemented\t\(coverage.implemented)
        coverage percent\t\(String(format: "%.1f", coverage.percentage))
        lifecycle entry points\t\(run.entryPoints)
        terminal outcomes\t\(run.terminalOutcomes)
        completed outcomes\t\(run.completed)
        fault outcomes\t\(runtime.tally.faultTotal)
        pending outcomes\t\(run.pending)
        native calls\t\(runtime.tally.nativeCallTotal)
        unknown native calls\t\(runtime.tally.unimplementedNativeTotal)
        native argument failures\t\(runtime.tally.nativeFailureTotal)
        deferred animations\t\(runtime.tally.deferredAnimationTotal)
        instructions executed\t\(runtime.tally.instructionsExecuted)
        tick seconds\t\(String(format: "%.2f", run.tickSeconds))
        instructions per second\t\(Int(Self.instructionRate(runtime: runtime, run: run)))

        Fault kinds
        \(faults)

        Top unknown natives
        \(unknown)
        """
    }

    private var logURL: URL {
        get throws { try logsDirectory.appending(path: "papyrus-m11-acceptance.log") }
    }

    private var logsDirectory: URL {
        get throws { try RepositoryLogs.directory() }
    }
}
