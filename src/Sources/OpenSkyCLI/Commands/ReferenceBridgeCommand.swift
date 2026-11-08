// `reference state|send|sync|follow|load|answer`: the Windows game through the OpenSkyBridge
// plugin (docs/tools/reference-game.md#the-bridge-plugin).

import Foundation
import OpenSkyAgentControl
import OpenSkyCLIArguments
import OpenSkyReference

enum ReferenceBridgeCommand {
    static func state(arguments _: ReferenceArguments.State) throws {
        let state = try liveBridge().state
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try print(String(bytes: encoder.encode(state), encoding: .utf8) ?? "")
    }

    static func send(arguments: ReferenceArguments.Send) async throws {
        try await liveBridge().bridge.run(arguments.commands)
        print("[INFO] The Windows game ran \(arguments.commands.count) command(s).")
    }

    static func sync(arguments: ReferenceArguments.Sync) async throws {
        let view = try ReferenceCommand.runningView(GameCommandOptions(arguments.game))
        let state = try await liveBridge().bridge.sendView(view, toggles: arguments.batch.toggles)
        print("[INFO] The Windows game stands at \(place(of: state)).")
    }

    static func follow(arguments: ReferenceArguments.Follow) throws {
        guard let view = try liveBridge().state.view else {
            throw CLIError.failure("the Windows game has no player in a cell yet")
        }
        let options = GameCommandOptions(arguments.game)
        let session = try GameCommand.connect(options)
        let reply: AgentReply
        do {
            reply = try session.call(
                "debug.view", args: AgentViewTarget(view).arguments,
                timeout: options.timeout ?? 130
            )
        } catch {
            throw CLIError.failure("\(error.code.rawValue): \(error.message)")
        }
        guard reply.ok else {
            throw CLIError.failure(reply.error?.message ?? "debug.view failed")
        }
        print("[INFO] OpenSky follows the Windows game.")
    }

    static func load(arguments: ReferenceArguments.Load) async throws {
        let prefix = try ReferenceCommand.readyPrefix()
        let save: String
        if let name = arguments.save {
            save = name
        } else if let newest = ReferenceLauncher.newestSave(in: prefix) {
            save = newest.lastPathComponent
        } else {
            throw CLIError.failure("the reference game has no save yet")
        }
        print("[INFO] Waiting for the Windows game's main menu, then loading \(save).")
        let state = try await ReferenceBridge(prefix: prefix).loadSave(named: save)
        print("[INFO] The Windows game stands at \(place(of: state)).")
    }

    static func answer(arguments: ReferenceArguments.Answer) async throws {
        let state = try await liveBridge().bridge.answer(arguments.button)
        let next = state.dialog.map { " The next message box: \($0.text)" } ?? ""
        print("[INFO] The Windows game took the answer.\(next)")
    }

    private static func liveBridge() throws
        -> (bridge: ReferenceBridge, state: ReferenceBridgeState)
    {
        let prefix = try ReferenceCommand.readyPrefix()
        let bridge = ReferenceBridge(prefix: prefix)
        guard let state = bridge.state() else {
            let missing = ReferenceBridgePart.missing(in: prefix).map(\.rawValue)
            let hint = missing.isEmpty ? "" : " Missing: \(missing.joined(separator: ", "))."
            throw CLIError.failure(ReferenceBridgeError.notRunning.localizedDescription + hint)
        }
        return (bridge, state)
    }

    private static func place(of state: ReferenceBridgeState) -> String {
        state.view?.place.map { place in
            switch place {
            case let .exterior(worldspace, grid): "\(worldspace) \(grid.x), \(grid.y)"
            case let .interior(editorID): editorID
            }
        } ?? "no cell"
    }
}

extension AgentViewTarget {
    /// The Windows game's view as `debug.view` takes it.
    init(_ view: ReferenceView) {
        self.init(
            feet: SIMD3(view.feet[0], view.feet[1], view.feet[2]), yawDegrees: view.yawDegrees,
            pitchDegrees: view.pitchDegrees, worldspace: view.worldspaceEditorID,
            interiorCell: view.interiorFormID, hour: view.gameHour, weather: view.weatherFormID
        )
    }
}
