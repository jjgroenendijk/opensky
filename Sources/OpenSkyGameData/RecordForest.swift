// A tree rebuilt from parent and previous-sibling links, as IDLE, CPTH, and
// the story-manager nodes store it. Broken links and cycles are counted, and
// the build never loops. See docs/formats/idle.md.

import Foundation

nonisolated public struct RecordForest<ID: Hashable & Sendable>: Sendable {
    public struct Link: Sendable {
        public let id: ID
        public let parent: ID?
        public let previousSibling: ID?

        public init(id: ID, parent: ID?, previousSibling: ID?) {
            self.id = id
            self.parent = parent
            self.previousSibling = previousSibling
        }
    }

    /// Nodes without a known parent, in sibling order.
    public private(set) var roots: [ID] = []
    /// Nodes that name a parent which is not in the forest. They stay roots.
    public private(set) var orphans: [ID] = []
    /// Nodes no root reaches, because they sit on or below a parent cycle.
    public private(set) var unreachable: [ID] = []
    /// Child groups whose previous-sibling chain is split or loops. They keep input order.
    public private(set) var brokenSiblingChains = 0
    /// Levels below the roots plus one; 0 for an empty forest.
    public private(set) var maximumDepth = 0
    private var childrenByParent: [ID: [ID]] = [:]
    private var parents: [ID: ID] = [:]

    public init(_ links: [Link]) {
        let known = Set(links.map(\.id))
        var rootLinks: [Link] = []
        var groups: [ID: [Link]] = [:]
        var parentOrder: [ID] = []
        for link in links {
            guard let parent = link.parent, known.contains(parent) else {
                if link.parent != nil {
                    orphans.append(link.id)
                }
                rootLinks.append(link)
                continue
            }
            if groups[parent] == nil {
                parentOrder.append(parent)
            }
            groups[parent, default: []].append(link)
            parents[link.id] = parent
        }
        // Roots form no sibling chain of their own, so a split there is not a break.
        let breaks = brokenSiblingChains
        roots = order(rootLinks)
        brokenSiblingChains = breaks
        for parent in parentOrder {
            childrenByParent[parent] = order(groups[parent] ?? [])
        }
        measure(known: links.map(\.id))
    }

    public func children(of id: ID) -> [ID] {
        childrenByParent[id] ?? []
    }

    public func parent(of id: ID) -> ID? {
        parents[id]
    }

    /// The root first, `id` last. Stops at a cycle instead of looping.
    public func path(to id: ID) -> [ID] {
        var path: [ID] = []
        var seen: Set<ID> = []
        var current: ID? = id
        while let node = current, seen.insert(node).inserted {
            path.append(node)
            current = parents[node]
        }
        return path.reversed()
    }

    private mutating func order(_ members: [Link]) -> [ID] {
        let ids = Set(members.map(\.id))
        var next: [ID: ID] = [:]
        var starts: [ID] = []
        for member in members {
            if
                let previous = member.previousSibling, ids.contains(previous),
                next[previous] == nil
            {
                next[previous] = member.id
            } else {
                starts.append(member.id)
            }
        }
        var ordered: [ID] = []
        var placed: Set<ID> = []
        for start in starts {
            var current: ID? = start
            while let node = current, placed.insert(node).inserted {
                ordered.append(node)
                current = next[node]
            }
        }
        let leftovers = members.map(\.id).filter { !placed.contains($0) }
        if starts.count > 1 || !leftovers.isEmpty {
            brokenSiblingChains += 1
        }
        return ordered + leftovers
    }

    private mutating func measure(known: [ID]) {
        var reached: Set<ID> = []
        var frontier = roots
        while !frontier.isEmpty {
            let level = frontier.filter { reached.insert($0).inserted }
            guard !level.isEmpty else { break }
            maximumDepth += 1
            frontier = level.flatMap { children(of: $0) }
        }
        unreachable = known.filter { !reached.contains($0) }
    }
}
