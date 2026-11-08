// `benchmark`: opens OpenSky.app with a tour request, waits for it to quit,
// then prints the summary from its result.json (docs/tools/benchmark.md).

import Foundation
import OpenSkyAssetCache
import OpenSkyCLIArguments
import OpenSkyGameData
import OpenSkyWorld
import OpenSkyWorldInterface

enum BenchmarkCommand {
    static func run(context: CLIContext, arguments: BenchmarkArguments) throws {
        let request = try makeRequest(arguments)
        guard let out = request.outDirectory else { return }
        let folder = URL(filePath: out, directoryHint: .isDirectory)
        if arguments.evict {
            let evicted = PageCacheEviction.evict(folders: evictFolders(context: context))
            print("[INFO] evicted \(evicted >> 20) MiB from the page cache")
        }
        let started = Date()
        try openApp(GameLaunch.locateApp(arguments.app), request: request, context: context)
        let resultURL = folder.appending(path: BenchmarkReport.resultFile)
        guard
            let data = try? Data(contentsOf: resultURL),
            let result = try? BenchmarkTourResult.decode(json: data),
            result.startedAt >= started.addingTimeInterval(-1)
        else {
            throw CLIError
                .failure("the app wrote no result to \(resultURL.path(percentEncoded: false)); "
                    + "the Benchmark log category says why")
        }
        BenchmarkReport.lines(for: result).forEach { print($0) }
        print("[INFO] result: \(folder.path(percentEncoded: false))")
        let failed = result.scenes.filter { $0.status == .failed }
        guard failed.isEmpty else {
            throw CLIError
                .failure("\(failed.count) scene(s) failed: " + failed.map(\.id)
                    .joined(separator: ", "))
        }
        print(result
            .stopped ? "[WARNING] the tour was stopped early" : "[ OK ] benchmark tour finished")
    }

    /// The game data and the asset cache: the app reads both, often from two disks.
    static func evictFolders(context: CLIContext) -> [URL] {
        let settings = AssetCacheSettings(
            store: PlayerSettingsStore(persistence: try? PlayerSettingsFile.defaultFile())
        )
        let cache = try? settings.effectiveFolder()
        return [context.root.dataURL] + (cache.map { [$0] } ?? [])
    }

    /// Checks every option here, so a typo fails before the app opens.
    static func makeRequest(_ arguments: BenchmarkArguments) throws -> BenchmarkRequest {
        var request = BenchmarkRequest()
        if let preset = arguments.preset {
            guard let parsed = BenchmarkPreset(rawValue: preset.rawValue) else {
                throw CLIError.failure("no benchmark preset \(preset.rawValue)")
            }
            request.preset = parsed
        }
        if let scenes = arguments.scenes {
            request.sceneIDs = scenes.items
        }
        request.overlay = !arguments.noOverlay
        request.captureScene = arguments.capture
        request.loadPasses = !arguments.noLoadPasses
        request.screenshots = arguments.screenshots
        request.muted = !arguments.sound
        request.quitWhenDone = !arguments.keepOpen
        do throws(BenchmarkRequestError) {
            request.display = try display(arguments)
            request.frameSize = try arguments.size.map(BenchmarkFrameSize.parse)
            for pair in arguments.settings?.items ?? [] {
                let (id, value) = try BenchmarkRequest.parseSetting(pair)
                request.settings[id] = value
            }
            let scenes = try request.scenes()
            if let capture = arguments.capture, !scenes.contains(where: { $0.id == capture }) {
                throw BenchmarkRequestError.unknownScene(capture)
            }
            _ = try request.settingOverrides()
        } catch {
            throw CLIError.usage(error.description)
        }
        let folder = arguments.out.map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? BenchmarkReport.defaultFolder(startedAt: Date())
        request.outDirectory = folder.standardizedFileURL.path(percentEncoded: false)
        return request
    }

    private static func display(
        _ arguments: BenchmarkArguments
    ) throws(BenchmarkRequestError) -> BenchmarkDisplay {
        switch (arguments.windowed, arguments.fullScreen) {
        case (true, true): throw .malformed("pick one of --windowed and --full-screen")
        case (true, false): .windowed
        case (false, true): .fullScreen
        case (false, false): .hidden
        }
    }

    /// `open -W` waits until the app quits after the tour. `-g` keeps a hidden
    /// run in the background, so the app in front keeps the focus.
    private static func openApp(_ app: URL, request: BenchmarkRequest, context: CLIContext) throws {
        var arguments = request.display == .hidden ? ["-W", "-n", "-g"] : ["-W", "-n"]
        arguments += [
            app.path(percentEncoded: false),
            "--env", "OPENSKY_DATA_ROOT=\(context.root.installURL.path(percentEncoded: false))"
        ]
        if request.captureScene != nil {
            arguments += ["--env", "MTL_CAPTURE_ENABLED=1"]
        }
        arguments += ["--args", BenchmarkRequest.appRequestArgument, request.encodedJSON]
        let place = request.display == .hidden ? "hidden, off the screen" : "in its window"
        print("[INFO] opening \(app.lastPathComponent); the tour runs \(place)")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/open")
        process.arguments = arguments
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.failure("open failed with status \(process.terminationStatus)")
        }
    }

    static func printScenes() {
        for scene in BenchmarkTour.scenes {
            let presets = BenchmarkPreset.allCases.filter { preset in
                preset.scenes().contains { $0.id == scene.id }
            }.map(\.rawValue).joined(separator: ",")
            print([scene.id, scene.group.rawValue, scene.shot.kind, scene.place.label, presets]
                .joined(separator: "\t"))
        }
    }
}
