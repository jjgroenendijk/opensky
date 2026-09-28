// Immutable PACK/NPC_ indexes and template resolution (issue #201). Built
// once from Skyrim.esm beside the other CellProviderIndexes stores.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public enum PackageResolveError: Error, Equatable {
    case missingPackage(FormID)
    case templateCycle([FormID])
}

nonisolated public enum PackageProcedureKind: Equatable, Sendable {
    case travel
    case wander
    case sandbox
    case sleep
    case eat
    case unsupported(String)
}

nonisolated public struct ResolvedPackage: Equatable, Sendable {
    public let package: Package
    public let template: Package?
    public let templateChain: [FormID]
    public let procedure: PackageProcedureKind

    public var location: Package.Location? {
        package.dataInputs.compactMap { input -> Package.Location? in
            guard case let .location(value) = input.value else { return nil }
            return value
        }.first
    }

    public var target: Package.Target? {
        package.dataInputs.compactMap { input -> Package.Target? in
            guard case let .target(value) = input.value else { return nil }
            return value
        }.first
    }
}

nonisolated public struct PackageStore: Sendable {
    public let packages: [UInt32: Package]
    public let actorTemplates: ActorTemplateResolver

    public static let empty = PackageStore(
        packages: [],
        actorTemplates: ActorTemplateResolver(actors: [:], leveledActors: [:])
    )

    public init(file: ESMFile) {
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        actorTemplates = ActorTemplateResolver.build(from: file, localized: localized)
        var decoded: [UInt32: Package] = [:]
        if let group = file.topGroup(of: "PACK"), let children = try? group.children() {
            for case let .record(record) in children where record.type == "PACK" {
                guard !record.isDeleted, let package = try? Package(record: record) else {
                    continue
                }
                decoded[record.formID] = package
            }
        }
        packages = decoded
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
            template: resolvedTemplate,
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
        if names.contains("travel") || names.contains("patrol") {
            return .travel
        }
        let name = package.procedureTypes.first ?? package.editorID ?? package.formID.description
        return .unsupported(name)
    }
}
