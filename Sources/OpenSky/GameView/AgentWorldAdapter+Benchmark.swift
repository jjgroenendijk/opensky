// `openskycli game benchmark`: runs the tour in this window and answers when it
// ends, with the result folder and the summary lines.

import Foundation
import OpenSkyAgentControl
import OpenSkyGameData
import OpenSkyWorld

extension AgentWorldAdapter {
    func benchmark(_ agentRequest: AgentBenchmarkRequest) throws(AgentFailure) -> AgentHandling {
        let tour = game.benchmarkWorld
        if agentRequest.stop {
            tour.stop()
            return .done(.success(["stopped": .bool(true)]))
        }
        guard !tour.isRunning else {
            throw AgentFailure(.notReady, "a benchmark tour is already running")
        }
        let request = try Self.tourRequest(agentRequest)
        let before = tour.runCount
        do {
            try tour.start(request)
        } catch {
            throw AgentFailure(.invalidArgument, error.description)
        }
        return .waiting(AgentWait { [weak tour] _ in
            guard let tour else {
                return .done(.failure(AgentFailure(.notReady, "the game window closed")))
            }
            guard tour.runCount > before, let run = tour.lastRun else { return .wait }
            return .done(.success(Self.json(run)))
        })
    }

    private static func tourRequest(
        _ agent: AgentBenchmarkRequest
    ) throws(AgentFailure) -> BenchmarkRequest {
        var request = BenchmarkRequest()
        if let preset = agent.preset {
            guard let parsed = BenchmarkPreset(rawValue: preset.lowercased()) else {
                throw AgentFailure(.invalidArgument, "preset must be quick, standard, or full")
            }
            request.preset = parsed
        }
        request.sceneIDs = agent.scenes.isEmpty ? nil : agent.scenes
        request.overlay = agent.overlay
        request.outDirectory = agent.out
        request.captureScene = agent.capture
        request.loadPasses = agent.loadPasses
        request.screenshots = agent.screenshots
        request.fullScreen = agent.fullScreen
        do {
            for pair in agent.settings {
                let (id, value) = try BenchmarkRequest.parseSetting(pair)
                request.settings[id] = value
            }
        } catch {
            throw AgentFailure(.invalidArgument, error.description)
        }
        return request
    }

    private static func json(_ run: BenchmarkRun) -> AgentJSON {
        let result = run.result
        return [
            "folder": .string(run.folder.path(percentEncoded: false)),
            "comparable": .bool(result.isComparable),
            "stopped": .bool(result.stopped),
            "failed": .init(result.scenes.filter { $0.status == .failed }.count),
            "writeError": .init(run.writeError),
            "summary": .array(BenchmarkReport.lines(for: result).map { .string($0) })
        ]
    }
}
