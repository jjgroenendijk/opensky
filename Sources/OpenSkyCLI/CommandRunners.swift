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

extension RecordArguments.Show: CLIRunnable {
    func execute() throws {
        try RecordCommand.show(context: context(), arguments: self)
    }
}

extension RecordArguments.Find: CLIRunnable {
    func execute() throws {
        try RecordFindCommand.run(context: context(), arguments: self)
    }
}

extension PluginsArguments: CLIRunnable {
    func execute() throws {
        try PluginsCommand.run(context: context())
    }
}

extension GapsArguments: CLIRunnable {
    func execute() throws {
        try GapsCommand.run(context: context(), arguments: self)
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
        try GraphicsCommand.preset(context: context(), name: name.rawValue)
    }
}

extension ESSArguments.Show: CLIRunnable {
    func execute() async throws {
        try await ESSCommand.show(arguments: self)
    }
}

extension ESSArguments.List: CLIRunnable {
    func execute() throws {
        try ESSCommand.list(arguments: self)
    }
}

extension GMSTArguments.Subject: CLIRunnable {
    func execute() throws {
        try GMSTCommand.run(context: context(), subject: subject)
    }
}

extension GMSTArguments.List: CLIRunnable {
    func execute() throws {
        try GMSTCommand.runList(context: context(), prefix: prefix)
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

extension EffectsArguments.Census: CLIRunnable {
    func execute() throws {
        try EffectsCommand.census(context: context())
    }
}

extension EffectsArguments.IMAD: CLIRunnable {
    func execute() throws {
        try EffectsCommand.sampleIMAD(context: context(), arguments: self)
    }
}

extension CellArguments: CLIRunnable {
    func execute() throws {
        try CellCommand.run(context: context(), arguments: self)
    }
}

extension ActorArguments.Appearance: CLIRunnable {
    func execute() throws {
        try ActorCommand.run(context: context(), arguments: self)
    }
}

extension ActorArguments.Values: CLIRunnable {
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

extension HKTArguments.Show: CLIRunnable {
    func execute() throws {
        try HKTCommand.show(context: context(), arguments: self)
    }
}

extension HKTArguments.Sweep: CLIRunnable {
    func execute() throws {
        try HKTCommand.sweep(context: context())
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

extension AudioArguments.Show: CLIRunnable {
    func execute() throws {
        try AudioCommand.runInfo(context: context(), path: asset.path)
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

extension RenderArguments: CLIRunnable {
    func execute() throws {
        try RenderCommand.run(context: context(), arguments: self)
    }
}

extension PreviewArguments: CLIRunnable {
    func execute() throws {
        try PreviewCommand.run(context: context(), arguments: self)
    }
}

extension BenchmarkArguments: CLIRunnable {
    func execute() throws {
        if list {
            BenchmarkCommand.printScenes()
            return
        }
        try BenchmarkCommand.run(context: context(), arguments: self)
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

extension ReferenceArguments.Status: CLIRunnable {
    func execute() {
        ReferenceCommand.status(arguments: self)
    }
}

extension ReferenceArguments.Check: CLIRunnable {
    func execute() async throws {
        try await ReferenceCommand.check(arguments: self)
    }
}

extension ReferenceArguments.Launch: CLIRunnable {
    func execute() async throws {
        try await ReferenceCommand.launch(arguments: self)
    }
}

extension ReferenceArguments.ExportView: CLIRunnable {
    func execute() throws {
        try ReferenceCommand.exportView(arguments: self)
    }
}

extension ReferenceArguments.Capture: CLIRunnable {
    func execute() throws {
        try ReferenceCapture.capture(arguments: self)
    }
}

extension ReferenceArguments.State: CLIRunnable {
    func execute() throws {
        try ReferenceBridgeCommand.state(arguments: self)
    }
}

extension ReferenceArguments.Send: CLIRunnable {
    func execute() async throws {
        try await ReferenceBridgeCommand.send(arguments: self)
    }
}

extension ReferenceArguments.Sync: CLIRunnable {
    func execute() async throws {
        try await ReferenceBridgeCommand.sync(arguments: self)
    }
}

extension ReferenceArguments.Follow: CLIRunnable {
    func execute() throws {
        try ReferenceBridgeCommand.follow(arguments: self)
    }
}

extension ReferenceArguments.Load: CLIRunnable {
    func execute() async throws {
        try await ReferenceBridgeCommand.load(arguments: self)
    }
}

extension ReferenceArguments.Answer: CLIRunnable {
    func execute() async throws {
        try await ReferenceBridgeCommand.answer(arguments: self)
    }
}

extension PexArguments: CLIRunnable {
    func execute() throws {
        try PexCommand.run(context: context(), arguments: self)
    }
}
