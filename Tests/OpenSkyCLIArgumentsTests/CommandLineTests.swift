// The command line keeps the names, typed options, and exit codes scripts rely on.

import ArgumentParser
import OpenSkyCLIArguments
import Testing

struct CommandLineTests {
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
        #expect(cell.grid.x == 6)
        #expect(cell.grid.y == -2)
        #expect(cell.refs)
    }

    @Test func aBadNumberFailsBeforeAnyGameDataLoads() {
        #expect(exitCode(["cell", "--x", "abc"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["render", "--out", "a.png", "--zoom", "50"])
            == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["render", "--out", "a.png", "--size", "0x10"])
            == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["actor", "values"]) == OpenSkyCommandLine.usageExitCode)
    }

    @Test func hkxRaisesEventsAndHoldsNumberVariables() throws {
        let probe = try command(
            [
                "hkx", "a.hkx", "--raise", "TakeOff", "--raise", "FlyStopDefault", "--set",
                "DistToGoal=0"
            ],
            as: HKXArguments.self
        )
        #expect(probe.raise == ["TakeOff", "FlyStopDefault"])
        #expect(probe.variables == ["DistToGoal=0"])
        #expect(exitCode(["hkx", "a.hkx", "--set", "Speed=1"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["hkx", "a.hkx", "--raise", "A", "--set", "Speed"])
            == OpenSkyCommandLine.usageExitCode)
    }

    @Test func pexTakesAScriptAndAFunction() throws {
        let pex = try command(
            ["pex", "MQ101QuestScript", "--function", "OnUpdate"], as: PexArguments.self
        )
        #expect(pex.script == "MQ101QuestScript")
        #expect(pex.function == "OnUpdate")
        #expect(exitCode(["pex"]) == OpenSkyCommandLine.usageExitCode)
    }

    @Test func installChecksTheGivenFolder() throws {
        let install = try command(["install", "--data-root", "/game"], as: InstallArguments.self)
        #expect(install.global.dataRoot == "/game")
    }

    @Test func renderTakesTypedValues() throws {
        let shot = try command(
            [
                "render",
                "--out",
                "a.png",
                "--time-of-day",
                "6",
                "--imad-at",
                "1",
                "--size",
                "640x360"
            ],
            as: RenderArguments.self
        )
        #expect(shot.out == "a.png")
        #expect(shot.timeOfDay == 6)
        #expect(shot.effects.imadAt == 1)
        #expect(shot.size == PixelSize(width: 640, height: 360))
        #expect(exitCode(["screenshot", "--out", "a.png"]) == OpenSkyCommandLine.usageExitCode)
    }

    @Test func previewTakesATargetAStageAndAngles() throws {
        let preview = try command(
            ["preview", "--ref", "1A26F", "--stage", "cell", "--angles", "all", "--yaw", "-30"],
            as: PreviewArguments.self
        )
        #expect(preview.reference == "1A26F")
        #expect(preview.stage == .cell)
        #expect(preview.angles?.items == ["all"])
        #expect(preview.yaw == -30)
        #expect(exitCode(["preview", "--stage", "garden"]) == OpenSkyCommandLine.usageExitCode)
    }

    @Test func benchmarkTakesAPresetScenesAndSettings() throws {
        let benchmark = try command(
            [
                "benchmark", "--preset", "quick", "--scenes", "whiterun,dragonsreach",
                "--set", "rendering.renderScale=1,rendering.gpuCulling=off",
                "--no-overlay", "--capture", "whiterun", "--no-load-passes", "--keep-open",
                "--evict", "--screenshots", "--windowed", "--out", "/tmp/run"
            ],
            as: BenchmarkArguments.self
        )
        #expect(benchmark.preset == .quick)
        #expect(benchmark.scenes?.items == ["whiterun", "dragonsreach"])
        #expect(benchmark.settings?.items == [
            "rendering.renderScale=1",
            "rendering.gpuCulling=off"
        ])
        #expect(benchmark.noOverlay && benchmark.noLoadPasses && benchmark.keepOpen && benchmark
            .evict)
        #expect(benchmark.capture == "whiterun")
        #expect(benchmark.screenshots)
        #expect(benchmark.windowed)
        #expect(benchmark.out == "/tmp/run")
        #expect(try command(["benchmark", "--list"], as: BenchmarkArguments.self).list)
        #expect(exitCode(["benchmark", "--preset", "huge"]) == OpenSkyCommandLine.usageExitCode)
    }

    @Test func oldNamesAreGone() {
        for old in [
            ["bench"],
            ["launch-bench"],
            ["screenshot"],
            ["asset-cache", "status"],
            ["actor-values"],
            ["record", "0x3C"],
            ["hkt", "a.hkt"],
            ["swf", "info", "a"],
            ["swf", "inventory-menu"],
            ["audio", "info", "a.xwm"],
            ["gmst", "bogus"]
        ] {
            #expect(exitCode(old) == OpenSkyCommandLine.usageExitCode, "\(old)")
        }
    }

    @Test func assetOptimisationTakesTypedSettings() throws {
        let build = try command(
            [
                "asset-optimisation",
                "build",
                "--texture-quality",
                "medium",
                "--max-texture-side",
                "2048"
            ],
            as: AssetCacheArguments.Build.self
        )
        #expect(build.options.settings.textureQuality == .medium)
        #expect(build.options.settings.maxTextureSide == 2048)
    }

    @Test func graphicsPresetNamesThePreset() throws {
        let preset = try command(["graphics", "preset", "ultra"], as: GraphicsArguments.Preset.self)
        #expect(preset.name == .ultra)
        _ = try command(["graphics", "status"], as: GraphicsArguments.Status.self)
    }

    @Test func gameWordsPassThroughToTheApp() throws {
        let send = try command(
            ["game", "--text", "input", "press", "jump", "--frames", "3"],
            as: GameArguments.Send.self
        )
        #expect(send.game.text)
        #expect(send.words == ["input", "press", "jump", "--frames", "3"])
        let help = try command(["game", "state", "av", "--help"], as: GameArguments.Send.self)
        #expect(help.words == ["state", "av", "--help"])
        let launch = try command(["game", "launch"], as: GameArguments.Launch.self)
        #expect(launch.survivalMode == .off)
        let asking = try command(
            ["game", "launch", "--survival-mode", "ask"], as: GameArguments.Launch.self
        )
        #expect(asking.survivalMode == .ask)
    }

    @Test func gapsRunsTheAskedSectionsInReportOrder() throws {
        let all = try command(["gaps"], as: GapsArguments.self)
        #expect(all.sections == GapsArguments.sectionKeys)
        let some = try command(
            ["gaps", "--only", "perks,Papyrus", "--limit", "5"],
            as: GapsArguments.self
        )
        #expect(some.sections == ["papyrus", "perks"])
        #expect(some.limit == 5)
        #expect(exitCode(["gaps", "--only", "dance"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["gaps", "--limit", "0"]) == OpenSkyCommandLine.usageExitCode)
    }

    @Test func modesAreRealSubcommands() throws {
        _ = try command(["record", "show", "0x3C"], as: RecordArguments.Show.self)
        _ = try command(["ess", "list", "saves"], as: ESSArguments.List.self)
        _ = try command(["ess", "show", "a.ess", "--offline"], as: ESSArguments.Show.self)
        _ = try command(["hkt", "sweep"], as: HKTArguments.Sweep.self)
        _ = try command(["hkt", "show", "a.hkt"], as: HKTArguments.Show.self)
        _ = try command(["effects", "census"], as: EffectsArguments.Census.self)
        let imad = try command(
            ["effects", "imad", "Fade", "--at", "0.5"],
            as: EffectsArguments.IMAD.self
        )
        #expect(imad.at == 0.5)
        let combat = try command(["gmst", "combat"], as: GMSTArguments.Subject<CombatSubject>.self)
        #expect(combat.subject == "combat")
        let list = try command(["gmst", "list", "fCombat"], as: GMSTArguments.List.self)
        #expect(list.prefix == "fCombat")
        _ = try command(
            ["actor", "appearance", "--npc", "Heimskr"],
            as: ActorArguments.Appearance.self
        )
        _ = try command(["actor", "values", "--race", "NordRace"], as: ActorArguments.Values.self)
        _ = try command(["menu", "container", "--mode", "barter"], as: MenuArguments.Container.self)
        _ = try command(["vfs", "cat", "a.nif", "--out", "b"], as: VFSArguments.Cat.self)
        _ = try command(
            ["audio", "voice-sweep", "--names-only"],
            as: AudioArguments.VoiceSweep.self
        )
        _ = try command(
            ["swf", "movie-probe", "--movie", "a.swf"],
            as: SWFArguments.MovieProbe.self
        )
    }

    @Test func recordFindTakesFiltersAndFields() throws {
        let find = try command(
            [
                "record", "find", "--type", "WEAP", "--where", "keywords=WeapTypeDagger",
                "--where", "data.damage>5", "--fields", "editorID,data.damage", "--limit", "3"
            ],
            as: RecordArguments.Find.self
        )
        #expect(find.type == "WEAP")
        #expect(find.filters == ["keywords=WeapTypeDagger", "data.damage>5"])
        #expect(find.fields?.items == ["editorID", "data.damage"])
        #expect(find.limit == 3)
        #expect(exitCode(["record", "find", "--type", "WEAPON"]) == OpenSkyCommandLine
            .usageExitCode)
        #expect(exitCode(["record", "find", "--type", "WEAP", "--count", "--json"])
            == OpenSkyCommandLine.usageExitCode)
    }

    @Test func referenceTakesAWindowSizeAndBatchToggles() throws {
        let launch = try command(
            ["reference", "launch", "--width", "1920", "--height", "1080", "--steam-wait", "5"],
            as: ReferenceArguments.Launch.self
        )
        #expect(launch.window.width == 1920 && launch.window.height == 1080)
        #expect(launch.steamWait == 5)
        let export = try command(
            ["reference", "export-view", "--no-hide-menus", "--freeze"],
            as: ReferenceArguments.ExportView.self
        )
        #expect(!export.batch.hideMenus && export.batch.freeze)
        _ = try command(["reference", "capture"], as: ReferenceArguments.Capture.self)
        _ = try command(["reference", "check"], as: ReferenceArguments.Check.self)
        _ = try command(["reference", "status"], as: ReferenceArguments.Status.self)
        #expect(exitCode(["reference", "launch", "--width", "10"])
            == OpenSkyCommandLine.usageExitCode)
    }

    @Test func aUsageErrorExitsWithTwoAndHelpWithZero() {
        #expect(exitCode(["cell", "--bogus"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["no-such-command"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["vfs", "cat", "a.nif"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["record"]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["--help"]) == 0)
        #expect(exitCode(["help", "benchmark"]) == 0)
        #expect(exitCode([]) == OpenSkyCommandLine.usageExitCode)
        #expect(exitCode(["swf"]) == OpenSkyCommandLine.usageExitCode)
    }
}

private enum CommandLineTestError: Error {
    case notACommand
}

extension CommandLineTests {
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
}
