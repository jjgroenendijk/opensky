import Foundation
import OpenSkyFormatsCore
public import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct ResolvedPackage: Equatable, Sendable {
    public let package: Package
    public let templateChain: [FormID]
    /// The procedure the package is known by: the main one of its tree.
    public let procedure: PackageProcedureKind
    /// The template's "Ride Horse if possible?" input: Travel and Patrol both have one.
    public let ridesHorse: Bool
    /// The last template of the chain, or the package itself; it holds the tree.
    public let definition: Package
    public let tree: PackageProcedureTree

    public init(
        package: Package,
        templateChain: [FormID],
        procedure: PackageProcedureKind,
        ridesHorse: Bool,
        definition: Package,
        tree: PackageProcedureTree
    ) {
        self.package = package
        self.templateChain = templateChain
        self.procedure = procedure
        self.ridesHorse = ridesHorse
        self.definition = definition
        self.tree = tree
    }
}
