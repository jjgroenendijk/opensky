// The command line keeps the names, options, and exit codes scripts rely on.

import ArgumentParser
import OpenSkyCLIArguments
import Testing

struct CommandLineTests {
    private func command<T>(_ arguments: [String], as _: T.Type) throws -> T {
        guard case let .run(command) = OpenSkyCommandLine.outcome(arguments) else {
            Issue.record("\(arguments) did not parse to a command")
            throw CommandLineTestError.notACommand
        }
        return try #require(command as? T)
    }

    private func exitCode(_ arguments: [String]) -> Int32? {
        guard case let .exit(code, _) = OpenSkyCommandLine.outcome(arguments) else { return nil }
        return code
    }

    @Test func theDataRootWorksBeforeAndAfterTheCommand() throws {
        let before = try command(["--data-root", "/a", "cell"], as: CellArguments.self)
        let after = try command(["cell", "--data-root", "/b"], as: CellArguments.self)
        #expect(before.global.dataRoot == "/a")
        #expect(after.global.dataRoot == "/b")
    }

    @Test func theRootKeepsADataRootGivenWithoutACommand() throws {
        let root = try OpenSkyCommandLine.parseAsRoot(["--data-root", "/a"])
        #expect((root as? OpenSkyCommandLine)?.global.dataRoot == "/a")
    }

    @Test func aNegativeGridValueIsAValueNotAnOption() throws {
        let cell = try command(["cell", "--x", "6", "--y", "-2", "--refs"], as: CellArguments.self)
        #expect(cell.grid.x == "6")
        #expect(cell.grid.y == "-2")
        #expect(cell.refs)
    }

    @Test func renderIsAnAliasOfScreenshot() throws {
        let shot = try command(
            ["render", "--out", "a.png", "--time-of-day", "6", "--imad-at", "1"],
            as: ScreenshotArguments.self
        )
        #expect(shot.out == "a.png")
        #expect(shot.timeOfDay == "6")
        #expect(shot.effects.imadAt == "1")
    }

    @Test func benchKeepsItsBudgetAndCacheOptionNames() throws {
        let bench = try command(
            [
                "bench", "--fly-path", "--footprint-cap-mb", "900", "--budget-ms", "20",
                "--asset-cache", "--limit-gib", "8", "--no-lod-prebuild"
            ],
            as: BenchArguments.self
        )
        #expect(bench.flyPath)
        #expect(bench.budgets.footprintCapMb == "900")
        #expect(bench.budgetMs == "20")
        #expect(bench.assets.assetCache)
        #expect(bench.assets.cache.limitGib == "8")
        #expect(bench.noLodPrebuild)
    }

    @Test func gameWordsPassThroughToTheApp() throws {
        let send = try command(
            ["game", "--text", "input", "press", "jump", "--frames", "3"],
            as: GameArguments.Send.self
        )
        #expect(send.game.text)
        #expect(send.words == ["input", "press", "jump", "--frames", "3"])
        let launch = try command(
            ["game", "launch", "--mode", "developer"],
            as: GameArguments.Launch.self
        )
        #expect(launch.mode == "developer")
    }

    @Test func nestedCommandsKeepTheirNames() throws {
        _ = try command(["vfs", "ls", "meshes"], as: VFSArguments.List.self)
        _ = try command(["vfs", "cat", "a.nif", "--out", "b"], as: VFSArguments.Cat.self)
        _ = try command(
            ["audio", "voice-sweep", "--names-only"],
            as: AudioArguments.VoiceSweep.self
        )
        _ = try command(
            ["swf", "movie-probe", "--movie", "a.swf"],
            as: SWFArguments.MovieProbe.self
        )
        _ = try command(["asset-cache", "io-bench"], as: AssetCacheArguments.IOBench.self)
        _ = try command(["ess", "list", "saves"], as: ESSArguments.self)
    }

    @Test func aUsageErrorExitsWithTwoAndHelpWithZero() {
        #expect(exitCode(["cell", "--bogus"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["no-such-command"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["vfs", "cat", "a.nif"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["--help"]) == 0)
        #expect(exitCode(["help", "bench"]) == 0)
        #expect(exitCode([]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["swf"]) == OpenSkyCommandLine.usageExitCode)
    }
}

private enum CommandLineTestError: Error {
    case notACommand
}
