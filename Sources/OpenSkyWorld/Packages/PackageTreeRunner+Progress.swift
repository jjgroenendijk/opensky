// What the tree does after a procedure ends: the next child of a sequence, the end
// of a simultaneous branch, and the end or restart of the whole tree.

import OpenSkyFormatsESM

nonisolated extension PackageTreeRunner {
    /// True when the procedure succeeded, false when it failed, nil while it runs. A
    /// seated sit counts as success when it completes the package (`FNAM`).
    func finished(_ node: Int) -> Bool? {
        guard let leaf = running[node] else { return nil }
        switch leaf.machine.state {
        case .complete: return true
        case .failed: return false
        case .seated where leaf.leaf.completesPackage: return true
        default: return nil
        }
    }

    @MainActor
    mutating func settle(_ node: Int, host: inout some PackageTreeHost) {
        guard let success = finished(node), let leaf = running[node]?.leaf else { return }
        retire(node)
        if success, leaf.completesPackage {
            completePackage()
            return
        }
        propagate(from: node, success: success, host: &host)
    }

    /// Drops a finished procedure. A find hands what it found to its object list.
    mutating func retire(_ node: Int) {
        guard let leaf = running.removeValue(forKey: node) else { return }
        lastFinished = leaf.machine
        if mover == node {
            mover = nil
        }
        let output = PackageProcedureParameters.findOutput
        if
            leaf.leaf.kind == .find, leaf.machine.state == .complete,
            leaf.leaf.inputIndexes.indices.contains(output),
            let list = leaf.leaf.inputIndexes[output]
        {
            objectLists[list] = leaf.machine.found
        }
    }

    mutating func completePackage() {
        completions += 1
        outcome = .succeeded
        for node in runningNodes {
            retire(node)
        }
    }

    @MainActor
    private mutating func propagate(
        from node: Int, success: Bool, host: inout some PackageTreeHost
    ) {
        var child = node
        var succeeded = success
        while outcome == nil, let parent = tree.nodes[child].parent {
            switch tree.nodes[parent].content {
            case .branch(.sequence) where succeeded:
                let next = advanceSequence(
                    parent, from: (cursors[parent] ?? 0) + 1, host: &host
                )
                guard next != .running else { return }
                succeeded = next == .succeeded
            case .branch(.simultaneous):
                if succeeded {
                    stopSubtree(of: parent)
                } else {
                    live[parent]?.remove(child)
                    guard live[parent]?.isEmpty != false else { return }
                }
            default:
                break
            }
            child = parent
        }
        if outcome == nil {
            rootEnded(success: succeeded, host: &host, restarts: true)
        }
    }

    /// A root with the repeat flag starts again; one that ends at once does not, so a
    /// tree of instant procedures cannot loop within one frame.
    @MainActor
    mutating func rootEnded(success: Bool, host: inout some PackageTreeHost, restarts: Bool) {
        guard outcome == nil else { return }
        if success {
            completions += 1
        }
        if success, restarts, tree.nodes[0].repeats, enter(0, host: &host) == .running {
            return
        }
        outcome = success ? .succeeded : .failed
    }

    /// Stops every procedure below `node`, as a simultaneous branch does when one child ends.
    mutating func stopSubtree(of node: Int) {
        for leaf in runningNodes where isDescendant(leaf, of: node) {
            running.removeValue(forKey: leaf)
            if mover == leaf {
                mover = nil
            }
        }
    }

    private func isDescendant(_ node: Int, of ancestor: Int) -> Bool {
        var current = tree.nodes[node].parent
        while let parent = current {
            if parent == ancestor {
                return true
            }
            current = tree.nodes[parent].parent
        }
        return false
    }
}
