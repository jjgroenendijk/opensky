// Starts every interface movie with no bridge installed and ticks it, then counts what
// the AS2 runtime lacked and which menus talk to the engine with no bridge here.
// A bridge answers GameDelegate calls, so those are counted per movie, not as
// runtime gaps. Reads of names a movie never set are counted apart, because Flash
// answers them with `undefined` too. `openskycli gaps` prints it. Names and counts only.

import Foundation
import OpenSkyFormatsSWF
import OpenSkyGameData

nonisolated public struct MenuGapSweep {
    public static let ticks = 10

    public private(set) var movieCount = 0
    public private(set) var loadFailures: [String] = []
    /// Menu movie path -> GameDelegate names it registers or calls.
    private(set) var engineMovies: [String: Set<String>] = [:]
    /// AS2 names the runtime does not provide -> hits over all movies.
    private(set) var missingNames: [String: Int] = [:]
    private(set) var unimplementedOpcodes: [String: Int] = [:]
    private(set) var faultKinds: [String: Int] = [:]
    /// Reads of names Flash does not define and no movie set, with their distinct names.
    public private(set) var unsetReads = 0
    private(set) var unsetNames: Set<String> = []

    public var unsetNameCount: Int {
        unsetNames.count
    }

    public init() {}

    /// Movies that talk to the engine and have no bridge, by GameDelegate names.
    public var unbridgedMovies: [(name: String, count: Int)] {
        engineMovies.filter { !MenuMovieBridges.moviePaths.contains($0.key) }
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    public var bridgedMovieCount: Int {
        engineMovies.keys.filter(MenuMovieBridges.moviePaths.contains).count
    }

    /// Missing names, unimplemented opcodes, and faults in one ranked list.
    public var runtimeGaps: [(name: String, count: Int)] {
        let rows = missingNames.map { (name: "missing \($0.key)", count: $0.value) }
            + unimplementedOpcodes.map { (name: "opcode \($0.key)", count: $0.value) }
            + faultKinds.map { (name: "fault \($0.key)", count: $0.value) }
        return rows.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }

    /// A movie directly in `interface\`. One in a subfolder, such as
    /// `inventory components\`, is a part another menu loads.
    static func isMenuMovie(_ path: String) -> Bool {
        path.split(separator: "\\").count == 2
    }

    public static func run(loader: SWFMovieLoader) -> MenuGapSweep {
        var sweep = MenuGapSweep()
        var limits = AS2Limits.standard
        limits.tallyNames = 4096
        for path in loader.moviePaths() {
            sweep.movieCount += 1
            do {
                let runtime = try SWFMovieRuntime(
                    movieScene: loader.load(path: path),
                    limits: limits
                )
                runtime.start()
                for _ in 0 ..< ticks {
                    runtime.advance()
                }
                sweep.record(runtime, path: path)
            } catch {
                sweep.loadFailures.append("\(path): \(error)")
            }
        }
        return sweep
    }

    private mutating func record(_ runtime: SWFMovieRuntime, path: String) {
        let tally = runtime.tally
        let calls = runtime.invokeLog.entries.filter { $0.direction == .movieToEngine }.map(\.name)
        let engineNames = Set(runtime.movieCallbackNames + calls)
        for (name, count) in tally.missingNames where !engineNames.contains(name) {
            missingNames[name, default: 0] += count
        }
        unsetReads += tally.unsetTotal
        unsetNames.formUnion(tally.unsetNames.keys)
        for entry in tally.rankedUnimplemented {
            unimplementedOpcodes[entry.name, default: 0] += entry.count
        }
        for fault in tally.faults {
            faultKinds[fault.kind, default: 0] += 1
        }
        if !engineNames.isEmpty, Self.isMenuMovie(path) {
            engineMovies[path.lowercased()] = engineNames
        }
    }
}
