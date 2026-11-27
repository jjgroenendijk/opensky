// The ranking a headless sweep prints: each problem with the subjects it stops, most
// subjects first (docs/tools/headless-sweeps.md).

import Foundation

nonisolated public struct HeadlessSweepReport: Sendable, Equatable {
    public struct Row: Sendable, Equatable {
        public let problem: String
        /// Subjects hit, at most the number of examples asked for, in the order seen.
        public let examples: [String]
        public let count: Int

        public init(problem: String, examples: [String], count: Int) {
            self.problem = problem
            self.examples = examples
            self.count = count
        }
    }

    /// Keyed by the lowercased problem, because Papyrus names ignore case and scripts spell
    /// one native several ways.
    private var subjects: [String: [String]] = [:]
    private var seen: [String: Set<String>] = [:]
    private var spelling: [String: String] = [:]
    /// Every subject the sweep ran, with or without a problem.
    public private(set) var ran = 0

    public init() {}

    public mutating func noteRun() {
        ran += 1
    }

    /// One problem met by one subject. The same pair noted twice counts once.
    public mutating func note(_ problem: String, subject: String) {
        let key = problem.lowercased()
        guard seen[key, default: []].insert(subject).inserted else { return }
        spelling[key] = spelling[key] ?? problem
        subjects[key, default: []].append(subject)
    }

    /// Subjects that met at least one problem.
    public var failed: Int {
        seen.values.reduce(into: Set<String>()) { $0.formUnion($1) }.count
    }

    public func ranked(examples: Int) -> [Row] {
        subjects.map { key, hit in
            Row(
                problem: spelling[key] ?? key, examples: Array(hit.prefix(examples)),
                count: hit.count
            )
        }
        .sorted { $0.count == $1.count ? $0.problem < $1.problem : $0.count > $1.count }
    }

    /// The fallback names whose count rose between two reads of the same run.
    public static func delta(before: [String: Int], after: [String: Int]) -> [String] {
        after.compactMap { name, count in count > before[name, default: 0] ? name : nil }.sorted()
    }

    /// Skips the game makes too: an event the script has no handler for, and a script
    /// the record marks removed.
    static let expectedSkips: Set = [
        "script skip event function not defined", "script skip VMAD script marked removed"
    ]

    /// The problem a fragment meets when the run notes `fallback` (`PapyrusTally.fallbacks`),
    /// or nil for a skip the game makes too.
    public static func fragmentProblem(_ fallback: String) -> String? {
        guard !expectedSkips.contains(fallback) else { return nil }
        let classes = [
            ("None from native ", "native returns None: "),
            ("property binding skip ", "property does not resolve: "),
            ("unimplemented native ", "native does nothing yet: "),
            ("stubbed native ", "native does nothing yet: "),
            ("deferred animation ", "native does nothing yet: "),
            ("failed native ", "runtime error: "),
            ("fault ", "runtime error: "),
            ("script skip ", "script does not attach: ")
        ]
        for (prefix, problem) in classes where fallback.hasPrefix(prefix) {
            return problem + fallback.dropFirst(prefix.count)
        }
        return fallback
    }

    /// `name<TAB>count` lines, most counted first: the table each headless run writes.
    public static func fallbackTable(_ fallbacks: [(name: String, count: Int)]) -> String {
        fallbacks.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
            .map { "\($0.name)\t\($0.count)\n" }.joined()
    }

    /// The report as text: a header line, then one line per problem with its examples.
    public func text(unit: String, limit: Int?, examples: Int) -> String {
        var lines = ["\(ran) \(unit) run, \(failed) with a problem, \(subjects.count) problems"]
        let rows = ranked(examples: examples)
        for row in rows.prefix(limit ?? rows.count) {
            lines.append("\(row.count)\t\(row.problem)\t\(row.examples.joined(separator: ", "))")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
