// One CLI connection: numbers the requests and reads until each reply,
// passing the stream lines of a waiting command to a callback.

import Foundation

nonisolated public final class AgentClientSession {
    public let client: AgentSocketClient
    public let hello: AgentHello
    private var nextID = 1

    public init(path: String, connectTimeout: Double) throws(AgentFailure) {
        client = AgentSocketClient(path: path)
        hello = try client.connect(timeout: connectTimeout)
    }

    /// Sends one request and blocks until its reply or `timeout` seconds pass.
    public func call(
        _ command: String,
        args: [String: AgentJSON] = [:],
        timeout: Double,
        onEvent: (AgentEvent) -> Void = { _ in }
    ) throws(AgentFailure) -> AgentReply {
        let request = AgentRequest(id: nextID, command: command, args: args)
        nextID += 1
        try client.send(request)
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else {
                throw AgentFailure(.timeout, "\(command): no reply within \(Int(timeout)) s")
            }
            let line = try client.readLine(timeout: remaining)
            if let stream = try? JSONDecoder().decode(AgentStreamLine.self, from: line) {
                if stream.id == request.id {
                    onEvent(stream.event)
                }
                continue
            }
            let reply = try AgentLineCodec.decode(AgentReply.self, from: line)
            if reply.id == request.id {
                return reply
            }
        }
    }
}
