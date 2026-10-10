// Runs each parsed command: resolves the data root, then calls the command's code.

import OpenSkyCLIArguments

extension CLICommandArguments {
    func context() throws -> CLIContext {
        try CLIContext.resolve(dataRootOverride: global.dataRoot)
    }
}

extension VFSArguments.List: CLIRunnable {
    func execute() throws {
        try VFSCommand.list(context: context(), arguments: self)
    }
}

extension VFSArguments.Cat: CLIRunnable {
    func execute() throws {
        try VFSCommand.cat(context: context(), arguments: self)
    }
}

extension RecordArguments: CLIRunnable {
    func execute() throws {
        try RecordCommand.run(context: context(), arguments: self)
    }
}

extension PluginsArguments: CLIRunnable {
    func execute() throws {
        try PluginsCommand.run(context: context())
    }
}

extension InstallArguments: CLIRunnable {
    func execute() throws {
        try InstallCommand.run(dataRoot: global.dataRoot)
    }
}

extension GraphicsArguments.Status: CLIRunnable {
    func execute() throws {
        try GraphicsCommand.status(context: context())
    }
}

extension GraphicsArguments.Preset: CLIRunnable {
    func execute() throws {
        try GraphicsCommand.preset(context: context(), name: name.lowercased())
    }
}

extension ESSArguments: CLIRunnable {
    func execute() async throws {
        try await ESSCommand.run(arguments: self)
    }
}

extension GMSTArguments: CLIRunnable {
    func execute() throws {
        try GMSTCommand.run(context: context(), arguments: self)
    }
}

extension ArcheryArguments: CLIRunnable {
    func execute() throws {
        try ArcheryCommand.run(context: context(), arguments: self)
    }
}

extension FootstepArguments: CLIRunnable {
    func execute() throws {
        try FootstepCommand.run(context: context(), arguments: self)
    }
}

extension EffectsArguments: CLIRunnable {
    func execute() throws {
        try EffectsCommand.run(context: context(), arguments: self)
    }
}

extension CellArguments: CLIRunnable {
    func execute() throws {
        try CellCommand.run(context: context(), arguments: self)
    }
}

extension ActorArguments: CLIRunnable {
    func execute() throws {
        try ActorCommand.run(context: context(), arguments: self)
    }
}

extension ActorValuesArguments: CLIRunnable {
    func execute() throws {
        try ActorValueCommand.run(context: context(), arguments: self)
    }
}

extension CollisionArguments: CLIRunnable {
    func execute() throws {
        try CollisionCommand.run(context: context(), arguments: self)
    }
}

extension InteriorArguments: CLIRunnable {
    func execute() throws {
        try InteriorCommand.run(context: context(), arguments: self)
    }
}

extension LODArguments: CLIRunnable {
    func execute() throws {
        try LODCommand.run(context: context(), arguments: self)
    }
}

extension NIFArguments: CLIRunnable {
    func execute() throws {
        try AssetCommand.runNIF(context: context(), arguments: self)
    }
}

extension DDSArguments: CLIRunnable {
    func execute() throws {
        try AssetCommand.runDDS(context: context(), arguments: self)
    }
}

extension HKXArguments: CLIRunnable {
    func execute() throws {
        try HKXCommand.run(context: context(), arguments: self)
    }
}

extension HKTArguments: CLIRunnable {
    func execute() throws {
        try HKTCommand.run(context: context(), arguments: self)
    }
}

extension SkeletonArguments: CLIRunnable {
    func execute() throws {
        try SkeletonCommand.run(context: context(), arguments: self)
    }
}

extension AnimationArguments: CLIRunnable {
    func execute() throws {
        try AnimationCommand.run(context: context(), arguments: self)
    }
}

extension AudioArguments.Info: CLIRunnable {
    func execute() throws {
        try AudioCommand.runInfo(context: context(), path: key)
    }
}

extension AudioArguments.Sweep: CLIRunnable {
    func execute() throws {
        try AudioSweep.run(context: context())
    }
}

extension AudioArguments.VoiceSweep: CLIRunnable {
    func execute() throws {
        try AudioVoiceSweep.run(context: context(), arguments: self)
    }
}

extension AudioArguments.AACCheck: CLIRunnable {
    func execute() throws {
        try AudioAACCheck.run(context: context(), arguments: self)
    }
}

extension ScreenshotArguments: CLIRunnable {
    func execute() throws {
        try RenderCommand.run(context: context(), arguments: self)
    }
}

extension BenchArguments: CLIRunnable {
    func execute() throws {
        try BenchCommand.run(context: context(), arguments: self)
    }
}

extension BenchmarkArguments: CLIRunnable {
    func execute() throws {
        try BenchmarkCommand.run(context: context(), arguments: self)
    }
}

extension LaunchBenchArguments: CLIRunnable {
    func execute() async throws {
        try await LaunchBenchCommand.run(context: context())
    }
}

extension AssetCacheArguments.Build: CLIRunnable {}
extension AssetCacheArguments.Check: CLIRunnable {}
extension AssetCacheArguments.Clear: CLIRunnable {}
extension AssetCacheArguments.Status: CLIRunnable {}
extension AssetCacheArguments.Extract: CLIRunnable {}
extension AssetCacheArguments.IOBench: CLIRunnable {}
extension AssetCacheArguments.Measure: CLIRunnable {}

extension AssetCacheActionArguments {
    func execute() async throws {
        try await AssetCacheCommand.run(context: context(), action: Self.action, arguments: options)
    }
}

extension AssetCacheArguments.Compare: CLIRunnable {
    func execute() throws {
        try AssetCacheCommand.compare(arguments: self)
    }
}

extension GameArguments.Launch: CLIRunnable {
    func execute() throws {
        try GameLaunch.run(arguments: self)
    }
}

extension GameArguments.Attach: CLIRunnable {
    func execute() throws {
        try GameCommand.attach(arguments: self)
    }
}

extension GameArguments.Run: CLIRunnable {
    func execute() throws {
        try GameScriptRun.run(arguments: self)
    }
}

extension GameArguments.Send: CLIRunnable {
    func execute() throws {
        try GameCommand.send(arguments: self)
    }
}
