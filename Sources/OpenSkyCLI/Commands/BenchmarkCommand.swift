// `benchmark`: opens OpenSky.app with a tour request, waits for it to quit,
// then prints the summary from its result.json (docs/tools/benchmark.md).

import Foundation
import OpenSkyAssetCache
import OpenSkyCLIArguments
import OpenSkyGameData
import OpenSkyWorld

enum BenchmarkCommand {
    static func run(context: CLIContext, arguments: BenchmarkArguments) throws {
        let request = try makeRequest(arguments)
        guard let out = request.outDirectory else { return }
        let folder = URL(filePath: out, directoryHint: .isDirectory)
        if arguments.evict {
            let evicted = PageCacheEviction.evict(folders: [context.root.dataURL])
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
                .failure("the app wrote no result to \(resultURL.path(percentEncoded: false))")
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

    /// Checks every option here, so a typo fails before the app opens.
    static func makeRequest(_ arguments: BenchmarkArguments) throws -> BenchmarkRequest {
        var request = BenchmarkRequest()
        if let preset = arguments.preset {
            guard let parsed = BenchmarkPreset(rawValue: preset.lowercased()) else {
                throw CLIError.usage("--preset must be quick, standard, or full")
            }
            request.preset = parsed
        }
        if let scenes = arguments.scenes {
            request.sceneIDs = scenes.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        request.overlay = !arguments.noOverlay
        request.captureScene = arguments.capture
        request.loadPasses = !arguments.noLoadPasses
        request.quitWhenDone = !arguments.keepOpen
        do throws(BenchmarkRequestError) {
            for pair in arguments.settings {
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

    /// `open -W` waits until the app quits after the tour.
    private static func openApp(_ app: URL, request: BenchmarkRequest, context: CLIContext) throws {
        var arguments = [
            "-W", "-n", app.path(percentEncoded: false),
            "--env", "OPENSKY_DATA_ROOT=\(context.root.installURL.path(percentEncoded: false))"
        ]
        if request.captureScene != nil {
            arguments += ["--env", "MTL_CAPTURE_ENABLED=1"]
        }
        arguments += ["--args", BenchmarkRequest.appRequestArgument, request.encodedJSON]
        print("[INFO] opening \(app.lastPathComponent); the tour runs in its window")
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
