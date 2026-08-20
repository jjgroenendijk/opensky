// Env-gated M11.1 acceptance over the user's read-only vanilla PEX corpus.

import Foundation
@testable import opensky
import Testing

struct PapyrusAcceptanceRealDataTests {
    private struct RunEvidence {
        let entryPoints: Int
        let terminalOutcomes: Int
        let completed: Int
        let pending: Int
    }

    private static let entryPointNames = [
        "OnInit", "OnLoad", "OnPlayerLoadGame"
    ]

    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func closesHeadlessNativeAcceptance() throws {
        let root = try #require(Self.dataRoot)
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
        // 47 before the `Actor` family (issue #375), 56 after it, 58 once
        // 16.7 (issue #424) added `StartCombat` and `StopCombat`, and 69 once
        // 19.11 (issue #474) added the eleven spell natives — every one of
        // those twenty-two is referenced by the vanilla corpus, which is what
        // chose them. The progression items brought it to 78: three
        // actor-value writes (issue #496), the three perk natives (issue #497),
        // the two skill natives (issue #498) and `Actor.GetLevel` (issue #499).
        // `Game.GetPerkPoints` and `Game.ModPerkPoints` are SKSE functions and
        // the vanilla corpus references neither, so they add nothing here.
        #expect(coverage == PexNativeCoverage(implemented: 78, referenced: 508))
        #expect(run.entryPoints == 577)
        #expect(run.pending == 0)
        #expect(run.terminalOutcomes == 577)
        #expect(run.completed == 240)
        #expect(runtime.tally.faultTotal == 337)
        #expect(runtime.tally.nativeCallTotal == 536)
        #expect(runtime.tally.unimplementedNativeTotal == 323)
        // The `Quest` family (issue #322), the `Actor` family (issue #375,
        // widened by #424), the spell family (issue #474) and the progression
        // families (issues #496 through #499) are registered but need a world,
        // and this acceptance runs the corpus headless: their calls reach a
        // native that refuses honestly instead of falling through to the
        // unimplemented tally, which is where these 134 moved from. 130 before
        // the progression natives, 118 before the spell natives, 117 before
        // `StartCombat` and `StopCombat`, and 108 before the `Actor` family
        // landed.
        #expect(runtime.tally.nativeFailureTotal == 134)
        #expect(runtime.tally.deferredAnimationTotal == 18)
        #expect(runtime.tally.rankedFaultKinds.map(\.name) == [
            "typeMismatch", "invalidJump", "invalidOperand"
        ])
        #expect(runtime.tally.rankedFaultKinds.map(\.count) == [231, 93, 13])
        #expect(runtime.tally.rankedUnimplementedNatives.first?.name
            == "ReferenceAlias.AddInventoryEventFilter")
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
        for _ in 0 ..< 256 {
            clock = GameClock(
                totalGameSeconds: clock.totalGameSeconds + GameClock.secondsPerDay
            )
            outcomes.append(contentsOf: scheduler.tick(gameClock: clock))
            if scheduler.pendingCount == 0 {
                break
            }
        }
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
                pending: scheduler.pendingCount
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

        Fault kinds
        \(faults)

        Top unknown natives
        \(unknown)
        """
    }

    private var logURL: URL {
        logsDirectory.appending(path: "papyrus-m11-acceptance.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
    }
}
