// The agent's view of a tour: its request in, the result folder and summary out.

import Foundation
public import OpenSkyAgentControl
import OpenSkyGameData
import OpenSkyWorld
import OpenSkyWorldInterface

extension BenchmarkWorldAdapter {
    public func start(_ agent: AgentBenchmarkRequest) throws(AgentFailure) {
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
        request.display = agent.fullScreen ? .fullScreen : agent.windowed ? .windowed : .hidden
        request.muted = !agent.sound
        do {
            request.frameSize = try agent.size.map(BenchmarkFrameSize.parse)
            for pair in agent.settings {
                let (id, value) = try BenchmarkRequest.parseSetting(pair)
                request.settings[id] = value
            }
        } catch {
            throw AgentFailure(.invalidArgument, error.description)
        }
        do {
            try start(request)
        } catch {
            throw AgentFailure(.invalidArgument, error.description)
        }
    }

    public var lastRunJSON: AgentJSON? {
        guard let run = lastRun else { return nil }
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
