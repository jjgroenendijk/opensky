// Behavior graph topology dump for `openskycli hkx` (todo 14.2), split out of
// HKXCommand.swift to stay under the file-size lint cap. Prints what the node
// class decoders read: the decode coverage of the whole file, then the node
// tree below the graph's root generator — state machines with their state names
// and transition counts, clip generators with their animation paths, blender
// children with their weights.
//
// Output is plain text and stable enough for tools/probe.sh to grep.

import Foundation

enum HKXTopologyDump {
    /// Nodes listed verbatim before the walk collapses into per-class totals;
    /// the master behavior graph walks to thousands of nodes.
    private static let nodeListLimit = 40
    /// Deepest level printed, so a dump stays a shape rather than a transcript.
    private static let depthLimit = 4

    /// Prints the decode report and, for a behavior file, the node tree. A file
    /// with no `hkbBehaviorGraph` prints the report alone.
    static func print(file: HKXFile) {
        guard let graph = try? HKXObjectGraph(file: file) else {
            printError("[WARNING] object graph unavailable, skipping topology")
            return
        }
        printReport(HKBDecodeReport.decodeAll(in: graph))
        guard
            let behavior = HKBBehaviorGraph.graphs(in: graph).first,
            let root = behavior.rootGenerator
        else { return }
        printTopology(HKBGraphTopology.walk(from: root, in: graph))
    }

    private static func printReport(_ report: HKBDecodeReport) {
        Swift.print("decoded objects: \(report.decodedTotal)")
        for (name, count) in report.decodedCounts.sorted(by: byFrequency) {
            Swift.print("  \(name) \(count)")
        }
        if report.skippedTotal > 0 {
            Swift.print("objects with no decoder: \(report.skippedTotal)")
            for (name, count) in report.skippedCounts.sorted(by: byFrequency) {
                Swift.print("  \(name) \(count)")
            }
        }
        if report.failedTotal > 0 {
            Swift.print("objects that failed to decode: \(report.failedTotal)")
            for (name, count) in report.failedCounts.sorted(by: byFrequency) {
                Swift.print("  \(name) \(count)")
            }
        }
        let misreads = report.unresolved.filter { $0.miss != .noFixup }
        if !misreads.isEmpty {
            printError("[WARNING] \(misreads.count) misread members "
                + "(a null optional reports noFixup and is not counted here)")
            for reference in misreads.prefix(nodeListLimit) {
                printError("  \(reference.field) at 0x"
                    + String(format: "%x", reference.objectOffset)
                    + " — \(reference.miss.rawValue)")
            }
        }
    }

    private static func printTopology(_ topology: HKBGraphTopology) {
        Swift.print("graph nodes reached from the root generator: \(topology.nodes.count)")
        for node in topology.nodes.prefix(nodeListLimit) where node.depth <= depthLimit {
            let indent = String(repeating: "  ", count: node.depth + 1)
            let name = node.object.nodeName.map { " \"\($0)\"" } ?? ""
            Swift.print(indent + node.object.className + name
                + " — " + node.object.summary)
        }
        let hidden = topology.nodes.count - min(topology.nodes.count, nodeListLimit)
        if hidden > 0 {
            Swift.print("  ... \(hidden) more nodes")
        }
        if !topology.skippedClassCounts.isEmpty {
            Swift.print("reached classes with no decoder:")
            for (name, count) in topology.skippedClassCounts.sorted(by: byFrequency) {
                Swift.print("  \(name) \(count)")
            }
        }
        if topology.unregisteredTargetCount > 0 {
            Swift.print("references to unregistered locations: "
                + "\(topology.unregisteredTargetCount)")
        }
    }

    /// Report order: most frequent first, ties alphabetical, matching the
    /// class histogram the container dump already prints.
    private static func byFrequency(
        _ lhs: (key: String, value: Int),
        _ rhs: (key: String, value: Int)
    ) -> Bool {
        (lhs.value, rhs.key) > (rhs.value, lhs.key)
    }
}
