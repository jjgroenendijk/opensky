// Index of the rare global mouse handlers in one running movie. Flash sends
// onMouseMove, onMouseDown, and onMouseUp to every clip that defines them, but
// walking the whole display tree on every pointer event is unnecessary.

import Foundation

nonisolated final class SWFGlobalMouseHandlerRegistry: AS2ObjectMutationObserver {
    private struct ActiveClip {
        let node: SWFDisplayObject
        let depthPath: [UInt16]
    }

    private var candidates: [ObjectIdentifier: SWFDisplayHandle] = [:]
    private var prototypeDependents:
        [ObjectIdentifier: [ObjectIdentifier: SWFDisplayHandle]] = [:]
    private var dependenciesByNode: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]

    var count: Int {
        candidates.count
    }

    func observe(_ node: SWFDisplayObject) {
        node.object.mutationObserver = self
        observePrototypeChain(of: node)
        refresh(node)
    }

    func refresh(_ node: SWFDisplayObject) {
        let identifier = ObjectIdentifier(node)
        guard node.isClip, hasGlobalHandler(node) else {
            candidates[identifier] = nil
            return
        }
        if let handle = node.object.hostPayload as? SWFDisplayHandle {
            candidates[identifier] = handle
        }
    }

    /// Live candidates in the same highest-depth-first preorder as the former
    /// full-tree walk.
    func activeClips(in root: SWFDisplayObject) -> [SWFDisplayObject] {
        var active: [ActiveClip] = []
        var staleIdentifiers: [ObjectIdentifier] = []
        for (identifier, handle) in candidates {
            guard
                let node = handle.target,
                let depthPath = path(of: node, from: root),
                hasGlobalHandler(node)
            else {
                staleIdentifiers.append(identifier)
                continue
            }
            active.append(ActiveClip(node: node, depthPath: depthPath))
        }
        for identifier in staleIdentifiers {
            candidates[identifier] = nil
        }
        active.sort(by: precedes)
        return active.map(\.node)
    }

    func object(_ object: AS2Object, didMutateProperty name: String) {
        if Self.handlerNames.contains(name), let node = SWFDisplayObject.resolve(object) {
            refresh(node)
        }
        refreshDependents(of: object)
    }

    func objectDidMutatePrototype(_ object: AS2Object) {
        if let node = SWFDisplayObject.resolve(object) {
            observePrototypeChain(of: node)
            refresh(node)
        }
        refreshDependents(of: object)
    }

    private func refreshDependents(of prototype: AS2Object) {
        let identifier = ObjectIdentifier(prototype)
        guard let dependents = prototypeDependents[identifier] else {
            return
        }
        for handle in dependents.values {
            guard let node = handle.target else {
                continue
            }
            observePrototypeChain(of: node)
            refresh(node)
        }
    }

    private func observePrototypeChain(of node: SWFDisplayObject) {
        guard let handle = node.object.hostPayload as? SWFDisplayHandle else {
            return
        }
        let nodeIdentifier = ObjectIdentifier(node)
        clearPrototypeDependencies(of: nodeIdentifier)
        var dependencies: Set<ObjectIdentifier> = []
        var prototype = node.object.prototype
        var steps = 0
        while let object = prototype, steps < AS2Object.prototypeChainLimit {
            object.mutationObserver = self
            let identifier = ObjectIdentifier(object)
            prototypeDependents[identifier, default: [:]][nodeIdentifier] = handle
            dependencies.insert(identifier)
            prototype = object.prototype
            steps += 1
        }
        dependenciesByNode[nodeIdentifier] = dependencies
    }

    private func clearPrototypeDependencies(of nodeIdentifier: ObjectIdentifier) {
        guard let dependencies = dependenciesByNode[nodeIdentifier] else {
            return
        }
        for identifier in dependencies {
            prototypeDependents[identifier]?[nodeIdentifier] = nil
            if prototypeDependents[identifier]?.isEmpty == true {
                prototypeDependents[identifier] = nil
            }
        }
    }

    private func hasGlobalHandler(_ node: SWFDisplayObject) -> Bool {
        if
            Self.handlerNames.contains(where: {
                node.object.lookup($0)?.property.value.functionValue != nil
            })
        {
            return true
        }
        guard let events = node.clipActions?.allEvents else {
            return false
        }
        return !events.isDisjoint(with: Self.clipEvents)
    }

    private func path(
        of node: SWFDisplayObject,
        from root: SWFDisplayObject
    ) -> [UInt16]? {
        guard node !== root else {
            return nil
        }
        var path: [UInt16] = []
        var current: SWFDisplayObject? = node
        var steps = 0
        while let walked = current, steps < SWFDisplayObject.maximumTreeDepth {
            guard let parent = walked.parent else {
                return nil
            }
            path.append(walked.depth)
            if parent === root {
                return path.reversed()
            }
            current = parent
            steps += 1
        }
        return nil
    }

    private func precedes(_ lhs: ActiveClip, _ rhs: ActiveClip) -> Bool {
        let sharedCount = min(lhs.depthPath.count, rhs.depthPath.count)
        for index in 0 ..< sharedCount where lhs.depthPath[index] != rhs.depthPath[index] {
            return lhs.depthPath[index] > rhs.depthPath[index]
        }
        return lhs.depthPath.count < rhs.depthPath.count
    }

    private static let handlerNames = Set(["onMouseMove", "onMouseDown", "onMouseUp"])
    private static let clipEvents: SWFClipEventFlags = [.mouseMove, .mouseDown, .mouseUp]
}
