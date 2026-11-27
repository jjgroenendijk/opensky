// The handlers `tools/shallow-handlers` lists from the source, and the gap rows they give
// once ranked by how often the data uses each one (docs/tools/gaps.md, "Shallow handlers").

import Foundation

nonisolated public struct ShallowHandlerList: Sendable, Equatable {
    public enum ParseError: Error, Equatable {
        /// A line that is not four tab-separated columns with a known area and state.
        case malformedLine(Int)
    }

    public enum Area: String, Sendable {
        case native, condition
    }

    public enum State: String, Sendable {
        case works, shallow
        /// Shallow because the game does nothing there either.
        case onPurpose = "on-purpose"
    }

    public struct Handler: Sendable, Equatable {
        public let state: State
        /// The constant a shallow body answers, or the reason it is shallow on purpose.
        public let detail: String
    }

    /// Handlers keyed by lowercase name: `script.function` or `*.function` for a native,
    /// the Creation Kit name for a condition function.
    public let handlers: [Area: [String: Handler]]

    public init(text: String) throws(ParseError) {
        var handlers: [Area: [String: Handler]] = [:]
        for (number, line) in text.split(separator: "\n").enumerated() {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
                .map(String.init)
            guard
                parts.count == 4, let area = Area(rawValue: parts[0]),
                let state = State(rawValue: parts[2])
            else { throw .malformedLine(number + 1) }
            let key = parts[1].lowercased()
            // One name registered twice works when either body works.
            if handlers[area]?[key]?.state == .works {
                continue
            }
            handlers[area, default: [:]][key] = Handler(state: state, detail: parts[3])
        }
        self.handlers = handlers
    }

    /// The handlers of `area` that the data uses, judged.
    public struct Gaps: Sendable, Equatable {
        public var done = 0
        /// Shallow handlers, most used first, each with its constant.
        public var left: [(name: String, count: Int)] = []
        /// Shallow on purpose, with the reason; these count as done.
        public var onPurpose: [String] = []

        public static func == (lhs: Gaps, rhs: Gaps) -> Bool {
            lhs.done == rhs.done && lhs.onPurpose == rhs.onPurpose
                && lhs.left.map(\.name) == rhs.left.map(\.name)
                && lhs.left.map(\.count) == rhs.left.map(\.count)
        }
    }

    /// `uses` maps each name the data uses, spelt like the keys, to its uses. A native whose
    /// registration names only the function, `*.function`, takes the uses of that function
    /// on every script.
    public func gaps(_ area: Area, uses: [String: Int]) -> Gaps {
        let lowered = Dictionary(uses.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: +)
        var byFunction: [String: Int] = [:]
        for (name, count) in lowered {
            if let dot = name.lastIndex(of: ".") {
                byFunction[String(name[name.index(after: dot)...]), default: 0] += count
            }
        }
        var gaps = Gaps()
        for (key, handler) in handlers[area] ?? [:] {
            let used = key.hasPrefix("*.")
                ? byFunction[String(key.dropFirst(2))] ?? 0
                : lowered[key] ?? 0
            guard used > 0 else { continue }
            switch handler.state {
            case .works:
                gaps.done += 1
            case .onPurpose:
                gaps.done += 1
                gaps.onPurpose.append("\(key): \(handler.detail)")
            case .shallow:
                gaps.left.append((name: "\(key) answers \(handler.detail)", count: used))
            }
        }
        gaps.left.sort { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
        gaps.onPurpose.sort()
        return gaps
    }
}
