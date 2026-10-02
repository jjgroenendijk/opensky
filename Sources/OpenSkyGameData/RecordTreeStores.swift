// The record families stored as parent and previous-sibling trees: idles,
// camera paths, and story-manager nodes. Each store builds its tree once.
// See docs/formats/idle.md, camera-records.md, and story-manager.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct IdleStore: Sendable {
    public static let types: Set<FourCC> = ["IDLE", "IDLM", "ANIO", "AACT"]

    public let idles: TypedRecordStore<IdleAnimation>
    public let markers: TypedRecordStore<IdleMarker>
    public let animatedObjects: TypedRecordStore<AnimatedObject>
    /// The related-idle forest from each IDLE ANAM pair. AACT actions are nodes too,
    /// because the top idles of a tree name an action as their parent.
    public let forest: RecordForest<ResolvedFormID>
    public let actions: Set<ResolvedFormID>

    public init(index: RecordIndex) {
        idles = TypedRecordStore(
            index: index, types: ["IDLE"],
            decode: { try IdleAnimation(record: $0.record) }, editorID: \.editorID
        )
        markers = TypedRecordStore(
            index: index, types: ["IDLM"],
            decode: { try IdleMarker(record: $0.record) }, editorID: \.editorID
        )
        animatedObjects = TypedRecordStore(
            index: index, types: ["ANIO"],
            decode: { try AnimatedObject(record: $0.record) }, editorID: \.editorID
        )
        let actionIDs = index.orderedRecordIDs(of: ["AACT"])
        actions = Set(actionIDs)
        let actionLinks = actionIDs.map {
            RecordForest<ResolvedFormID>.Link(id: $0, parent: nil, previousSibling: nil)
        }
        let idleLinks = RecordForest.links(
            records: idles.records, index: index,
            parent: \.parent, previousSibling: \.previousSibling
        )
        forest = RecordForest(actionLinks + idleLinks)
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: Self.types))
    }

    /// The top idles of each tree: a root idle, or a child of an action.
    public var rootIdles: [ResolvedFormID] {
        forest.roots.flatMap { actions.contains($0) ? forest.children(of: $0) : [$0] }
    }

    /// The top idles under one AACT action, in sibling order.
    public func roots(underAction action: ResolvedFormID) -> [ResolvedRecord<IdleAnimation>] {
        forest.children(of: action).compactMap { idles.record($0) }
    }

    /// Root idles whose DATA names this animation group section, in sibling order.
    public func roots(inAnimationGroup section: UInt8) -> [ResolvedRecord<IdleAnimation>] {
        rootIdles.compactMap { idles.record($0) }
            .filter { $0.record.properties?.animationGroupSection == section }
    }

    /// The IDLA idles of a marker, in file order. A dangling entry is left out.
    public func idles(of marker: ResolvedRecord<IdleMarker>) -> [ResolvedRecord<IdleAnimation>] {
        marker.record.idles.compactMap { idles.resolve($0, fromPlugin: marker.sourcePlugin) }
    }
}

nonisolated public struct CameraPathStore: Sendable {
    public static let types: Set<FourCC> = ["CAMS", "CPTH"]

    public let shots: TypedRecordStore<CameraShot>
    public let paths: TypedRecordStore<CameraPath>
    /// The path tree from each CPTH ANAM pair.
    public let forest: RecordForest<ResolvedFormID>
    /// SNAM shots that resolve to no CAMS.
    public let danglingShotCount: Int

    public init(index: RecordIndex) {
        shots = TypedRecordStore(
            index: index, types: ["CAMS"],
            decode: { try CameraShot(record: $0.record) }, editorID: \.editorID
        )
        paths = TypedRecordStore(
            index: index, types: ["CPTH"],
            decode: { try CameraPath(record: $0.record) }, editorID: \.editorID
        )
        forest = RecordForest(
            records: paths.records, index: index,
            parent: \.parent, previousSibling: \.previousSibling
        )
        let paths = paths
        danglingShotCount = paths.records
            .flatMap { path in path.record.shots.compactMap { paths.link($0, from: path) } }
            .count(where: \.isDangling)
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: Self.types))
    }

    public func shots(of path: ResolvedRecord<CameraPath>) -> [ResolvedRecord<CameraShot>] {
        path.record.shots.compactMap { shots.resolve($0, fromPlugin: path.sourcePlugin) }
    }
}

nonisolated public struct StoryManagerStore: Sendable {
    public static let types: Set<FourCC> = ["SMBN", "SMQN", "SMEN"]

    public let nodes: TypedRecordStore<StoryManagerNode>
    public let forest: RecordForest<ResolvedFormID>
    private let rootsByEvent: [FourCC: [ResolvedFormID]]
    private let nodesByQuest: [ResolvedFormID: [ResolvedFormID]]

    public init(index: RecordIndex) {
        nodes = TypedRecordStore(
            index: index, types: Self.types,
            decode: { try StoryManagerNode(record: $0.record) }, editorID: \.editorID
        )
        forest = RecordForest(
            records: nodes.records, index: index,
            parent: \.parent, previousSibling: \.previousSibling
        )
        var rootsByEvent: [FourCC: [ResolvedFormID]] = [:]
        for root in forest.roots {
            guard let event = nodes.record(root)?.record.event else { continue }
            rootsByEvent[event, default: []].append(root)
        }
        var nodesByQuest: [ResolvedFormID: [ResolvedFormID]] = [:]
        for node in nodes.records {
            for entry in node.record.quests {
                guard let quest = index.resolvedID(entry.quest, fromPlugin: node.sourcePlugin)
                else { continue }
                nodesByQuest[quest, default: []].append(node.id)
            }
        }
        self.rootsByEvent = rootsByEvent
        self.nodesByQuest = nodesByQuest
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: Self.types))
    }

    /// The root event nodes for one event code, such as `KILL`, in sibling order.
    public func roots(forEvent event: FourCC) -> [ResolvedRecord<StoryManagerNode>] {
        (rootsByEvent[event] ?? []).compactMap { nodes.record($0) }
    }

    /// The quest nodes that can start `quest`.
    public func nodes(startingQuest quest: ResolvedFormID) -> [ResolvedRecord<StoryManagerNode>] {
        (nodesByQuest[quest] ?? []).compactMap { nodes.record($0) }
    }

    /// The event the node's tree hangs under, or nil when its root is not an event node.
    public func event(of node: ResolvedFormID) -> FourCC? {
        forest.path(to: node).first.flatMap { nodes.record($0)?.record.event }
    }
}
