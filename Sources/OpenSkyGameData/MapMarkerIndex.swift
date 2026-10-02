// Map markers per worldspace, read from the persistent references of each
// WRLD. A later plugin's copy of a marker wins. See docs/formats/placed-references.md.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct MapMarkerEntry: Equatable, Sendable {
    public let reference: ResolvedFormID
    public let worldspace: ResolvedFormID
    public let marker: MapMarker
    public let name: LString?
    public let position: SIMD3<Float>
    public let sourcePlugin: String
}

nonisolated public struct MapMarkerIndex: Sendable {
    private var entries: [ResolvedFormID: MapMarkerEntry] = [:]
    public private(set) var skippedRecords = SkippedRecords()

    /// `plugins` in load order, lowest priority first.
    public init(plugins: [(name: String, file: ESMFile)]) {
        for (name, file) in plugins {
            let resolver = FormIDResolver(
                pluginName: name,
                masters: skippedRecords.masters(of: file)
            )
            guard let top = file.topGroup(of: "WRLD") else { continue }
            for case let .group(group) in skippedRecords.children(of: top)
                where group.kind == .worldChildren
            {
                guard
                    let parent = group.parentFormID,
                    let world = resolver.resolve(FormID(parent))
                else { continue }
                let context = Context(plugin: name, localized: file.isLocalized, resolver: resolver)
                collect(in: group, world: world, context: context, persistent: false)
            }
        }
    }

    public var count: Int {
        entries.count
    }

    /// Markers of one worldspace, ordered by reference identity.
    public func markers(in worldspace: ResolvedFormID) -> [MapMarkerEntry] {
        entries.values.filter { $0.worldspace == worldspace }.sorted(by: Self.precedes)
    }

    private static func precedes(_ lhs: MapMarkerEntry, _ rhs: MapMarkerEntry) -> Bool {
        (lhs.reference.plugin, lhs.reference.objectID) < (
            rhs.reference.plugin,
            rhs.reference.objectID
        )
    }

    public var countsByWorldspace: [ResolvedFormID: Int] {
        entries.values.reduce(into: [:]) { $0[$1.worldspace, default: 0] += 1 }
    }

    /// Marker count per type name; an unnamed type shows as its number.
    public var typeHistogram: [String: Int] {
        entries.values.reduce(into: [:]) { histogram, entry in
            let type = entry.marker.type
            histogram[type?.name ?? type.map { "\($0.rawValue)" } ?? "none", default: 0] += 1
        }
    }

    private struct Context {
        let plugin: String
        let localized: Bool
        let resolver: FormIDResolver
    }

    private mutating func collect(
        in group: ESMGroup,
        world: ResolvedFormID,
        context: Context,
        persistent: Bool
    ) {
        for child in skippedRecords.children(of: group) {
            switch child {
            case let .group(inner):
                let isPersistent = inner.kind == .cellPersistentChildren
                guard isPersistent || inner.kind == .cellChildren else { continue }
                collect(in: inner, world: world, context: context, persistent: isPersistent)
            case let .record(record):
                guard persistent, record.type == "REFR", !record.isDeleted else { continue }
                add(record, world: world, context: context)
            }
        }
    }

    private mutating func add(_ record: ESMRecord, world: ResolvedFormID, context: Context) {
        guard
            let reference = skippedRecords.decode(record, using: PlacedReference.init(record:)),
            let marker = reference.mapMarker,
            let id = context.resolver.resolve(reference.formID)
        else { return }
        entries[id] = MapMarkerEntry(
            reference: id,
            worldspace: world,
            marker: marker,
            name: marker.name(localized: context.localized),
            position: reference.placement.position,
            sourcePlugin: context.plugin
        )
    }
}
