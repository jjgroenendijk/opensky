import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public struct PackageProcedureTree: Equatable, Sendable {
    public struct Node: Equatable, Sendable {
        public let content: Content
        public let conditions: [Condition]
        /// `PRCB` flag bit 0: start again when done.
        public let repeats: Bool
        public var children: [Int] = []
        public let parent: Int?

        public init(
            content: Content,
            conditions: [Condition],
            repeats: Bool,
            children: [Int] = [],
            parent: Int?
        ) {
            self.content = content
            self.conditions = conditions
            self.repeats = repeats
            self.children = children
            self.parent = parent
        }
    }

    public enum Branch: String, Equatable, Sendable {
        /// Runs its children in order and is done after the last.
        case sequence = "Sequence"
        /// Runs the first child whose conditions are true.
        case stacked = "Stacked"
        /// Runs one child with true conditions, picked at random.
        case random = "Random"
        /// Runs every child at once and is done when any child is.
        case simultaneous = "Simultaneous"
    }

    public enum Content: Equatable, Sendable {
        case branch(Branch)
        case procedure(PackageProcedureLeaf)
    }

    /// Node 0 is the root.
    public let nodes: [Node]

    public init(nodes: [Node]) {
        self.nodes = nodes
    }

    /// A one-procedure tree for a package with no branch list, which keeps the
    /// package's own procedure kind.
    public init(single kind: PackageProcedureKind) {
        nodes = [
            Node(
                content: .branch(.sequence),
                conditions: [],
                repeats: false,
                children: [1],
                parent: nil
            ),
            Node(content: .procedure(PackageProcedureLeaf(
                node: 1, kind: kind, completesPackage: true
            )), conditions: [], repeats: false, parent: 0)
        ]
    }
}

nonisolated public enum PackageTreeError: Error, Equatable, Sendable {
    /// A branch asks for more children than the list holds.
    case truncated(branch: Int)
    /// Branches remain after the root's last child.
    case trailingBranches(count: Int)
    case unknownBranchType(String)
}

/// One procedure of the tree, with the data input indexes it reads, in parameter order.
nonisolated public struct PackageProcedureLeaf: Equatable, Sendable {
    /// The leaf's node index in the tree.
    public let node: Int
    public let kind: PackageProcedureKind
    /// `PKC2`; 255 means the parameter has no input.
    public let inputIndexes: [Int8?]
    /// `FNAM`: the package is done when this procedure succeeds.
    public let completesPackage: Bool

    public init(
        node: Int, kind: PackageProcedureKind, inputIndexes: [Int8?] = [],
        completesPackage: Bool = false
    ) {
        self.node = node
        self.kind = kind
        self.inputIndexes = inputIndexes
        self.completesPackage = completesPackage
    }
}
