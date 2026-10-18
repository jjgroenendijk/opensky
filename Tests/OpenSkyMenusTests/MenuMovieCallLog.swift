// Records the engine-to-movie calls a bridge makes on a synthetic runtime: each
// name becomes a root function, which `callMovie` falls back to without a delegate.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyFormatsTesting

@MainActor
final class MenuMovieCallLog {
    private(set) var calls: [(name: String, arguments: [AS2Value])] = []

    init(runtime: SWFMovieRuntime, names: [String], on node: SWFDisplayObject? = nil) {
        for name in names {
            let record: (AS2CallContext) throws -> AS2Value = { [weak self] context in
                self?.calls.append((name, context.arguments))
                return .undefined
            }
            let target = (node ?? runtime.root).object
            AS2Natives.method(runtime.runtime, on: target, name: name, body: record)
        }
    }

    var names: [String] {
        calls.map(\.name)
    }

    func arguments(of name: String) -> [AS2Value]? {
        calls.last { $0.name == name }?.arguments
    }

    /// A synthetic movie with one empty frame.
    static func emptyRuntime() throws -> SWFMovieRuntime {
        try SWFRuntimeFixture.started(tags: [SWFDisplayFixture.showFrameTag])
    }
}

/// The events a bridge's host functions report.
@MainActor
final class MenuMovieEventLog<Event> {
    var events: [Event] = []

    func append(_ event: Event) {
        events.append(event)
    }
}
