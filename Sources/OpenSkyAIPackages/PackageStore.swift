// Immutable PACK/NPC_ indexes and template resolution, built once beside the
// other CellProviderIndexes stores.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldInterface

nonisolated public enum PackageResolveError: Error, Equatable {
    case missingPackage(FormID)
    case templateCycle([FormID])
}

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
}

nonisolated public struct PackageStore: Sendable {
    public let packages: [UInt32: Package]
    public let actorTemplates: ActorTemplateResolver
    /// The entries of every FLST, for the default and override package lists.
    public private(set) var formLists: [UInt32: [FormID]] = [:]
    /// PACK records that failed to decode.
    public private(set) var skippedRecords = SkippedRecords()

    /// The source plugin's translation of each package from a plugin whose
    /// FormIDs move; its conditions stay as written (`ConditionEvaluator`).
    private var translations: [UInt32: FormIDTranslation] = [:]

    public init(file: ESMFile) {
        self.init(loadOrder: LoadOrderPlugins(file: file))
    }

    /// Every plugin's PACK records; a later override wins. `leveling` is the
    /// session's, so a leveled actor's packages follow the entry it rolled.
    public init(loadOrder: LoadOrderPlugins, leveling: LeveledListRoller = LeveledListRoller()) {
        actorTemplates = ActorTemplateResolver.build(from: loadOrder, leveling: leveling)
        var skipped = SkippedRecords()
        let decoded = loadOrder.indexPluginRecords(of: "PACK", skipped: &skipped) {
            try (package: Package(record: $0), translation: $1.translation)
        }
        packages = decoded.mapValues(\.package)
        // A broken FLST belongs to the catalogue's own count, not the PACK one.
        var listsSkipped = SkippedRecords()
        formLists = loadOrder.indexRecords(of: "FLST", skipped: &listsSkipped) {
            try FormList(record: $0).entries.compactMap(\.self)
        }
        translations = decoded.compactMapValues {
            $0.translation.isIdentity ? nil : $0.translation
        }
        skippedRecords = skipped
    }

    public init(
        packages: [Package], actorTemplates: ActorTemplateResolver,
        formLists: [FormID: [FormID]] = [:]
    ) {
        self.packages = Dictionary(
            packages.map { ($0.formID.rawValue, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        self.actorTemplates = actorTemplates
        self.formLists = Dictionary(
            formLists.map { ($0.key.rawValue, $0.value) }, uniquingKeysWith: { first, _ in first }
        )
    }

    public func package(_ id: FormID) -> Package? {
        packages[id.rawValue]
    }

    /// A package by editor ID, ignoring case, or by hexadecimal FormID.
    public func packageID(named name: String) -> FormID? {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let hex = trimmed.lowercased().hasPrefix("0x") ? String(trimmed.dropFirst(2)) : trimmed
        if let raw = UInt32(hex, radix: 16), packages[raw] != nil {
            return FormID(raw)
        }
        return packages.values.first {
            $0.editorID?.caseInsensitiveCompare(trimmed) == .orderedSame
        }?.formID
    }

    /// How the conditions of package `id` translate into the load order; nil
    /// when its plugin keeps its FormIDs.
    public func translation(of id: FormID) -> FormIDTranslation? {
        translations[id.rawValue]
    }

    public func packageStack(for actorBase: FormID) throws -> ActorSourcedField<[FormID]> {
        try actorTemplates.resolvePackages(base: actorBase).packages
    }

    /// The actor's own stack, its default list, and its override lists, read through
    /// the template chain and the FLST records.
    public func packageLists(for actorBase: FormID) throws -> ActorPackageLists {
        let resolved = try actorTemplates.resolvePackages(base: actorBase)
        let ids = resolved.lists.value
        let entries = { (list: FormID?) in list.flatMap { formLists[$0.rawValue] } ?? [] }
        var overrides: [PackageSituation: [FormID]] = [:]
        for (situation, list) in [
            (PackageSituation.spectator, ids.spectator),
            (.observeDeadBody, ids.observeDeadBody),
            (.guardWarn, ids.guardWarn),
            (.combat, ids.combat)
        ] where !entries(list).isEmpty {
            overrides[situation] = entries(list)
        }
        return ActorPackageLists(
            own: resolved.packages.value, defaults: entries(ids.defaults), overrides: overrides
        )
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
        let procedure = Self.procedure(for: definition)
        return ResolvedPackage(
            package: concrete,
            templateChain: chain,
            procedure: procedure,
            ridesHorse: Self.ridesHorse(concrete, template: definition),
            definition: definition,
            tree: PackageProcedureTree.of(definition, fallback: procedure)
        )
    }

    /// Template inputs are matched by `UNAM` index, and named by the template's `BNAM`
    /// (docs/engine/package-schedules.md). A package that omits the input keeps the default.
    private static func ridesHorse(_ package: Package, template: Package) -> Bool {
        guard
            let index = template.details.templateInputs.first(where: {
                $0.name?.lowercased() == "ride horse if possible?"
            })?.index
        else { return false }
        for source in [package, template] {
            if
                let input = source.dataInputs.first(where: { $0.index == index }),
                case let .boolean(value) = input.value
            {
                return value
            }
        }
        return false
    }

    /// Procedure names, lowercased, that an actor runs.
    public static let runnableProcedures = PackageProcedureKind.runnableNames

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
        // SitTarget's tree also holds a Wait, which runs once the actor sits.
        if names.contains("sit") {
            return .sit
        }
        if names.contains("wait") {
            return .wait
        }
        guard let name = package.procedureTypes.first else {
            return .unsupported(package.editorID ?? package.formID.description)
        }
        return PackageProcedureKind(name: name)
    }
}
