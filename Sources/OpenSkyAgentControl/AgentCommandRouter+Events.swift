// `events`: list recent events, stream them, or wait for one kind.

import Foundation

extension AgentCommandRouter {
    /// How many events a plain listing returns at most.
    public static let eventListLimit = 200

    func events(_ args: AgentArguments, now: Double) throws(AgentFailure) -> AgentHandling {
        let follow = try args.bool("follow", default: false)
        let until = try args.optionalString("until")
        let timeout = try args.optionalFloat("timeout").map(Double.init)
        if let timeout, !(timeout > 0 && timeout <= 3600) {
            throw args.invalid("timeout", "in (0, 3600] seconds")
        }
        let filter = try Set(args.list("filter"))
        let unknown = filter.union(until.map { [$0] } ?? []).subtracting(AgentEventKind.all)
        if let name = unknown.sorted().first {
            throw AgentFailure(.invalidArgument, "events: unknown event kind \(name)")
        }
        // A listing defaults to the whole ring; a wait or a stream to what comes next.
        let since = try args.optionalInt("since")
            ?? (follow || until != nil ? eventLog.lastSeq : 0)
        guard follow || until != nil else {
            let listed = eventLog.events(after: since, kinds: filter).suffix(Self.eventListLimit)
            return .done(.success(["events": .array(listed.map(Self.json))]))
        }
        let deadline = timeout.map { now + $0 }
        return .waiting(eventWait(
            EventWaitPlan(follow: follow, until: until, filter: filter, deadline: deadline),
            since: since
        ))
    }

    private struct EventWaitPlan {
        let follow: Bool
        let until: String?
        let filter: Set<String>
        let deadline: Double?
    }

    private func eventWait(_ plan: EventWaitPlan, since: Int) -> AgentWait {
        var cursor = since
        var streamed = 0
        return AgentWait { [weak self] clock in
            guard let self else { return .done(.failure(AgentFailure(.notReady, "closed"))) }
            let fresh = eventLog.events(after: cursor)
            cursor = fresh.last?.seq ?? cursor
            var step = AgentWaitStep.wait
            for event in fresh {
                let wanted = plan.filter.isEmpty || plan.filter.contains(event.kind)
                if plan.follow, wanted || event.kind == plan.until {
                    step.events.append(event)
                    streamed += 1
                }
                if event.kind == plan.until {
                    step.finish = .success(["event": Self.json(event), "streamed": .init(streamed)])
                    return step
                }
            }
            if let deadline = plan.deadline, clock >= deadline {
                step.finish = plan.until == nil
                    ? .success(["streamed": .init(streamed)])
                    : .failure(AgentFailure(
                        .timeout,
                        "events: no \(plan.until ?? "") event in time"
                    ))
            }
            return step
        }
    }

    static func json(_ event: AgentEvent) -> AgentJSON {
        [
            "seq": .init(event.seq), "frame": .init(event.frame),
            "kind": .string(event.kind), "data": .object(event.data)
        ]
    }
}
