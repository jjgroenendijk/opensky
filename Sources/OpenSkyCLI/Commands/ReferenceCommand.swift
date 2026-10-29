// `reference`: the Windows game in its Wine prefix (docs/tools/reference-game.md). Every
// write lands in that prefix or in `.logs/`; the install OpenSky reads is only read.

import Foundation
import OpenSkyAgentControl
import OpenSkyCLIArguments
import OpenSkyGameData
import OpenSkyReference

enum ReferenceCommand {
    static func status(arguments _: ReferenceArguments.Status) {
        let prefix = ReferenceSettings.prefix()
        let status = ReferencePrefixStatus(prefix: prefix)
        print("[\(status.isReady ? "INFO" : "WARNING")] \(status.message)")
        if let wine = ReferenceSettings.wine(prefix: prefix) {
            print("[INFO] Wine: \(wine.path(percentEncoded: false))")
        } else {
            print("[WARNING] No Wine found. Run make reference-setup.")
        }
        guard status.isReady, let prefix else { return }
        let layout = ReferencePrefix(root: prefix)
        for part in ReferenceBridgePart.missing(in: layout) {
            print("[WARNING] The bridge lacks \(part.rawValue). Run make reference-bridge.")
        }
        let running = ReferenceBridge(prefix: layout).state() != nil
        print("[INFO] Bridge: \(running ? "the Windows game is running" : "no game running").")
    }

    static func check(arguments: ReferenceArguments.Check) async throws {
        let prefix = try readyPrefix()
        let install = try arguments.context().root.installURL
        print("[INFO] Hashing the master files of both installs.")
        async let opensky = ReferenceInstallFingerprint.read(
            gameDirectory: install, manifest: ReferenceWindow.manifest(forInstall: install)
        )
        async let reference = ReferenceInstallFingerprint.read(
            gameDirectory: prefix.gameDirectory, manifest: prefix.appManifest
        )
        let mismatches = try await ReferenceVersionCheck.compare(
            opensky: opensky, reference: reference
        )
        guard mismatches.isEmpty else {
            mismatches.forEach { print("[ERROR] \($0.line)") }
            throw CLIError.failure("the reference copy and the OpenSky install differ")
        }
        print("[INFO] Both installs hold the same Steam build and master files.")
    }

    static func launch(arguments: ReferenceArguments.Launch) async throws {
        let prefix = try readyPrefix()
        let run = try RunDirectory.create("reference-game")
        if !ReferenceLauncher.isSteamRunning() {
            print(
                "[INFO] Starting Windows Steam; waiting \(arguments.steamWait) s for it to log in."
            )
        }
        let frame = ReferenceWindowFrame(
            x: 0, y: 0, width: arguments.window.width, height: arguments.window.height
        )
        let preset = GraphicsPreset.allCases.first { arguments.preset.rawValue == "\($0)" }
        let options = ReferenceLaunchOptions(
            frame: frame, steamWait: arguments.steamWait, preset: preset
        )
        do {
            try await ReferenceLauncher.launch(prefix: prefix, options: options, logs: run)
        } catch let error as ReferenceLauncherError {
            throw CLIError.failure(error.localizedDescription)
        }
        print("[INFO] Started the game at \(frame.width) x \(frame.height).")
        print("[INFO] Wine output: \(run.path(percentEncoded: false))")
    }

    static func exportView(arguments: ReferenceArguments.ExportView) throws {
        let prefix = try readyPrefix()
        let view = try runningView(GameCommandOptions(arguments.game))
        let file = prefix.batchFile(named: ReferenceConsoleBatch.defaultName)
        try ReferenceConsoleBatch.write(view, toggles: arguments.batch.toggles, to: [file])
        print("[INFO] Wrote \(file.path(percentEncoded: false))")
        print(
            "[INFO] Type 'bat \(ReferenceConsoleBatch.defaultName)' in the reference game console."
        )
    }

    static func readyPrefix() throws -> ReferencePrefix {
        do {
            return try ReferenceLauncher.readyPrefix()
        } catch {
            throw CLIError.failure(error.localizedDescription)
        }
    }

    /// The view of the running OpenSky, read over the agent socket.
    static func runningView(_ options: GameCommandOptions) throws -> ReferenceView {
        let session = try GameCommand.connect(options)
        let reply: AgentReply
        do {
            reply = try session.call("state.view", timeout: options.timeout ?? 10)
        } catch {
            throw CLIError.failure("\(error.code.rawValue): \(error.message)")
        }
        guard reply.ok, let result = reply.result else {
            throw CLIError.failure(reply.error?.message ?? "state view gave no result")
        }
        let view = try JSONDecoder().decode(ReferenceView.self, from: JSONEncoder().encode(result))
        if !view.firstPerson {
            print("[WARNING] OpenSky is not in first person; the two cameras will differ.")
        }
        return view
    }
}

extension ReferenceBatchOptions {
    var toggles: ReferenceBatchToggles {
        ReferenceBatchToggles(hideMenus: hideMenus, freezeWorld: freeze)
    }
}
