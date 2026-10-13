// Which AI procedures the packages of the load order use, by packages, and which ones
// an actor can run. A package whose tree holds several procedures runs only one, so
// the others still count as left.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct PackageProcedureCensus: Sendable {
    /// Procedure name, lowercased -> packages whose resolved tree holds it.
    public private(set) var procedures = GapCounts()
    /// Failure kind -> packages.
    public private(set) var failures = GapCounts()
    public private(set) var packageCount = 0

    public init(store: PackageStore) {
        for raw in store.packages.keys.sorted() {
            packageCount += 1
            do {
                let resolved = try store.resolve(FormID(raw))
                let definition = resolved.templateChain.last.flatMap(store.package)
                    ?? resolved.package
                let names = Set(definition.procedureTypes.map { $0.lowercased() })
                for name in names {
                    procedures.add(name)
                }
            } catch {
                failures.add("package does not resolve: " + GapCounts.failureKind("\(error)"))
            }
        }
    }

    public static func isRunnable(_ procedure: String) -> Bool {
        PackageStore.runnableProcedures.contains(procedure)
    }
}
