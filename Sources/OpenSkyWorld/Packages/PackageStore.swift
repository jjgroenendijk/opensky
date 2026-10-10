// Immutable PACK/NPC_ indexes and template resolution, built once beside the
// other CellProviderIndexes stores.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public enum PackageResolveError: Error, Equatable {
    case missingPackage(FormID)
    case templateCycle([FormID])
}

nonisolated public enum PackageProcedureKind: Equatable, Sendable {
    case travel
    /// Walks a chain of linked references from a start marker.
    case patrol
    case wander
    case sandbox
    case sleep
    case eat
    /// Stays where it is and moves nowhere, as a rider in a cart does.
    case wait
    case unsupported(String)
}

nonisolated public struct ResolvedPackage: Equatable, Sendable {
    public let package: Package
    public let templateChain: [FormID]
    public let procedure: PackageProcedureKind
}

nonisolated public struct PackageStore: Sendable {
    public let packages: [UInt32: Package]
    public let actorTemplates: ActorTemplateResolver
    /// PACK records that failed to decode.
    public private(set) var skippedRecords = SkippedRecords()

    /// The source plugin's translation of each package from a plugin whose
    /// FormIDs move; its conditions stay as written (`ConditionEvaluator`).
    private var translations: [UInt32: FormIDTranslation] = [:]

    public init(file: ESMFile) {
        self.init(loadOrder: LoadOrderPlugins(file: file))
    }

    /// Every plugin's PACK records; a later override wins.
    public init(loadOrder: LoadOrderPlugins) {
        actorTemplates = ActorTemplateResolver.build(from: loadOrder)
        var skipped = SkippedRecords()
        let decoded = loadOrder.indexPluginRecords(of: "PACK", skipped: &skipped) {
            try (package: Package(record: $0), translation: $1.translation)
        }
        packages = decoded.mapValues(\.package)
        translations = decoded.compactMapValues {
            $0.translation.isIdentity ? nil : $0.translation
        }
        skippedRecords = skipped
    }

    public init(packages: [Package], actorTemplates: ActorTemplateResolver) {
        self.packages = Dictionary(
            packages.map { ($0.formID.rawValue, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.actorTemplates = actorTemplates
    }

    public func package(_ id: FormID) -> Package? {
        packages[id.rawValue]
    }

    /// How the conditions of package `id` translate into the load order; nil
    /// when its plugin keeps its FormIDs.
    public func translation(of id: FormID) -> FormIDTranslation? {
        translations[id.rawValue]
    }

    public func packageStack(for actorBase: FormID) throws -> ActorSourcedField<[FormID]> {
        try actorTemplates.resolvePackages(base: actorBase).packages
    }

    public func resolve(_ id: FormID) throws -> ResolvedPackage {
        guard let concrete = package(id) else { throw PackageResolveError.missingPackage(id) }
        var chain: [FormID] = [id]
        var seen: Set<FormID> = [id]
        var current = concrete
        var resolvedTemplate: Package?
        while let templateID = current.template {
            guard seen.insert(templateID).inserted else {
                throw PackageResolveError.templateCycle(chain + [templateID])
            }
            guard let next = package(templateID) else {
                throw PackageResolveError.missingPackage(templateID)
            }
            chain.append(templateID)
            resolvedTemplate = next
            current = next
        }
        let definition = resolvedTemplate ?? concrete
        return ResolvedPackage(
            package: concrete,
            templateChain: chain,
            procedure: Self.procedure(for: definition)
        )
    }

    private static func procedure(for package: Package) -> PackageProcedureKind {
        let names = package.procedureTypes.map { $0.lowercased() }
        let editorID = package.editorID?.lowercased() ?? ""
        if editorID == "eat" || names.contains("eat") {
            return .eat
        }
        if editorID == "sleep" || names.contains("sleep") {
            return .sleep
        }
        if names.contains("sandbox") {
            return .sandbox
        }
        if names.contains("wander") {
            return .wander
        }
        if names.contains("patrol") {
            return .patrol
        }
        if names.contains("travel") {
            return .travel
        }
        if names.contains("wait") {
            return .wait
        }
        let name = package.procedureTypes.first ?? package.editorID ?? package.formID.description
        return .unsupported(name)
    }
}
