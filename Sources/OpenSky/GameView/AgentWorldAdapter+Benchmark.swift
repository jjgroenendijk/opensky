// `openskycli game benchmark`: runs the tour in this window and answers when it
// ends, with the result folder and the summary lines.

import Foundation
import OpenSkyAgentControl
import OpenSkySessionInterface

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
        let before = tour.runCount
        try tour.start(agentRequest)
        return .waiting(AgentWait { [weak tour] _ in
            guard let tour else {
                return .done(.failure(AgentFailure(.notReady, "the game window closed")))
            }
            guard tour.runCount > before, let run = tour.lastRunJSON else { return .wait }
            return .done(.success(run))
        })
    }
}
