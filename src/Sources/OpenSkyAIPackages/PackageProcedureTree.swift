// A template's procedure tree, rebuilt from its flat branch list. Each branch that
// is not a procedure is followed by `PRCB` branch-count children, in pre-order.
// docs/formats/packages.md#procedure-tree; branch rules on the Creation Kit wiki
// page "Category:Package Templates".

import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

nonisolated extension PackageProcedureTree {
    public var leaves: [PackageProcedureLeaf] {
        nodes.compactMap {
            if case let .procedure(leaf) = $0.content {
                return leaf
            }
            return nil
        }
    }

    /// The template's tree, or the one-procedure tree when it has no usable branches.
    public static func of(_ template: Package, fallback: PackageProcedureKind) -> Self {
        guard
            !template.details.branches.isEmpty,
            let tree = attempt({ try Self(branches: template.details.branches) })
        else { return Self(single: fallback) }
        return tree
    }

    public init(branches: [PackageDetails.Branch]) throws(PackageTreeError) {
        var builder = Builder(branches: branches)
        try builder.read(parent: nil)
        guard builder.cursor == branches.count else {
            throw .trailingBranches(count: branches.count - builder.cursor)
        }
        self.init(nodes: builder.nodes)
    }

    private struct Builder {
        let branches: [PackageDetails.Branch]
        var nodes: [Node] = []
        var cursor = 0

        @discardableResult
        mutating func read(parent: Int?) throws(PackageTreeError) -> Int {
            guard cursor < branches.count else {
                throw .truncated(branch: parent ?? 0)
            }
            let branch = branches[cursor]
            let index = nodes.count
            cursor += 1
            let repeats = (branch.rootFlags ?? 0) & 1 != 0
            if branch.type == "Procedure" {
                let leaf = PackageProcedureLeaf(
                    node: index,
                    kind: PackageProcedureKind(name: branch.procedureType ?? ""),
                    inputIndexes: branch.dataInputIndexes
                        .map { $0 == 0xFF ? nil : Int8(bitPattern: $0) },
                    completesPackage: branch.successCompletesPackage
                )
                nodes.append(Node(
                    content: .procedure(leaf), conditions: branch.conditions,
                    repeats: repeats, parent: parent
                ))
                return index
            }
            guard let kind = Branch(rawValue: branch.type) else {
                throw .unknownBranchType(branch.type)
            }
            nodes.append(Node(
                content: .branch(kind), conditions: branch.conditions,
                repeats: repeats, parent: parent
            ))
            for _ in 0 ..< (branch.branchCount ?? 0) {
                let child = try read(parent: index)
                nodes[index].children.append(child)
            }
            return index
        }
    }
}
