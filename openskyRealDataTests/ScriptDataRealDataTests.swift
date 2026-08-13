// Env-gated VMAD sweep over the user's own Skyrim.esm plus a PEX metadata
// probe through the VFS. Game bytes remain read-only external input; only
// aggregate counts and sampled ReferenceKeys reach gitignored logs/.

import Foundation
@testable import opensky
import Testing

struct ScriptDataRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryVMADInSkyrimESM() throws {
        let root = try #require(Self.dataRoot)
        let file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let resolver = try file.pluginHeader().formIDResolver(pluginName: "Skyrim.esm")
        let recordIDs = Set(ESMWalk.recordTypeIndex(in: file).keys.map {
            $0 & 0x00FF_FFFF
        })

        var stats = sweep(file: file, resolver: resolver, recordIDs: recordIDs)
        var probe = PexBackingProbe(root: root)
        probe.inspect(stats.attachedScripts)
        stats.backing = probe.stats

        #expect(stats.vmadFields > 0, "Skyrim.esm contains no VMAD fields")
        #expect(stats.decodeFailures.isEmpty, "VMAD decode failures: \(stats.decodeFailures)")
        #expect(stats.unreadableRecords == 0, "records whose fields failed to parse")
        #expect(stats.sampledKeys.count == VMADStats.sampleLimit)
        #expect(stats.backing.inspectedAutomatic > 0, "no automatic PEX property was inspected")
        #expect(stats.backing.missingBacking == 0, "automatic PEX property lacks a backing name")
        #expect(stats.backing.missingVariable == 0, "PEX backing name does not name a variable")
        checkExactSkyrimCounts(stats)

        let report = stats.report
        print(report)
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        try report.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private func checkExactSkyrimCounts(_ stats: VMADStats) {
        #expect(stats.records == 869_687)
        #expect(stats.vmadFields == 16133)
        #expect(stats.scripts == 19936)
        #expect(stats.properties == 51145)
        #expect(stats.versions == [4: 2561, 5: 13572])
        #expect(stats.objectFormats == [1: 2705, 2: 13428])
        #expect(stats.propertyTypes == [
            1: 42885, 2: 179, 3: 3820, 4: 634, 5: 3625, 15: 2
        ])
        // No QUST or INFO fragments entries: M13.1 and M17.1 decode those
        // tails instead of skipping them. The alias-object count rose when
        // object properties inside quest alias scripts became visible.
        #expect(stats.skipped.ranked.map(\.count) == [
            12896, 557, 313, 7, 5
        ])
        #expect(stats.skipped.ranked.map(\.name) == [
            "alias object",
            "SCEN fragments",
            "PACK fragments",
            "removed property",
            "PERK fragments"
        ])
        #expect(stats.questFragmentSections == 856)
        #expect(stats.questFragments == 5108)
        #expect(stats.questAliasScriptSections == 2149)
        #expect(stats.directObjects == 29787)
        #expect(stats.nullObjects == 202)
        #expect(stats.danglingObjects == 39)
        #expect(stats.backing.scriptLoads == 4450)
        #expect(stats.backing.missingScripts == 0)
        #expect(stats.backing.missingProperties == 24)
        #expect(stats.backing.manualProperties == 199)
        #expect(stats.backing.inspectedAutomatic == 50915)
        #expect(stats.backing.conventionalNames == 50915)
        #expect(stats.backing.otherNames == 0)
    }

    private func sweep(
        file: ESMFile,
        resolver: FormIDResolver,
        recordIDs: Set<UInt32>
    ) -> VMADStats {
        var stats = VMADStats()
        ESMWalk.forEachRecord(in: file) { record in
            stats.records += 1
            guard let fields = try? record.fields() else {
                stats.unreadableRecords += 1
                return true
            }
            for field in fields where field.type == "VMAD" {
                stats.vmadFields += 1
                var data = ScriptData(ownerType: record.type)
                do {
                    _ = try data.decode(field: field)
                    stats.record(
                        data,
                        carrier: record.type,
                        resolver: resolver,
                        recordIDs: recordIDs
                    )
                } catch {
                    stats.decodeFailures[String(describing: error), default: 0] += 1
                }
            }
            return true
        }
        return stats
    }

    private struct VMADStats {
        static let sampleLimit = 32

        var records = 0
        var unreadableRecords = 0
        var vmadFields = 0
        var scripts = 0
        var properties = 0
        var versions: [Int16: Int] = [:]
        var objectFormats: [Int16: Int] = [:]
        var propertyTypes: [UInt8: Int] = [:]
        var carriers: [String: Int] = [:]
        /// QUST tails, which M13.1 decodes instead of skipping. Their alias
        /// scripts are ordinary script entries and are counted in `scripts`,
        /// `properties` and the PEX probe alongside the primary list.
        var questFragmentSections = 0
        var questFragments = 0
        var questAliasScriptSections = 0
        var skipped = ScriptDataTally()
        var decodeFailures: [String: Int] = [:]
        var directObjects = 0
        var nullObjects = 0
        var danglingObjects = 0
        var sampledKeys: [ReferenceKey] = []
        var attachedScripts: [AttachedScript] = []
        var backing = PexBackingStats()

        mutating func record(
            _ data: ScriptData,
            carrier: FourCC,
            resolver: FormIDResolver,
            recordIDs: Set<UInt32>
        ) {
            if let version = data.version {
                versions[version, default: 0] += 1
            }
            if let format = data.objectFormat {
                objectFormats[format.rawValue, default: 0] += 1
            }
            carriers["\(carrier)", default: 0] += 1
            skipped.merge(data.skipped)
            record(scripts: data.scripts, resolver: resolver, recordIDs: recordIDs)
            guard let section = data.questFragments else { return }
            questFragmentSections += 1
            questFragments += section.fragments.count
            questAliasScriptSections += section.aliasScripts.count
            for alias in section.aliasScripts {
                record(scripts: alias.scripts, resolver: resolver, recordIDs: recordIDs)
            }
        }

        mutating func record(
            scripts entries: [AttachedScript],
            resolver: FormIDResolver,
            recordIDs: Set<UInt32>
        ) {
            scripts += entries.count
            attachedScripts.append(contentsOf: entries)
            for script in entries {
                properties += script.properties.count
                for property in script.properties {
                    propertyTypes[property.type, default: 0] += 1
                    for object in property.value.objects {
                        record(
                            object,
                            resolver: resolver,
                            recordIDs: recordIDs
                        )
                    }
                }
            }
        }

        mutating func record(
            _ object: ScriptObjectReference,
            resolver: FormIDResolver,
            recordIDs: Set<UInt32>
        ) {
            guard !object.isAlias else { return }
            guard !object.formID.isNull else {
                nullObjects += 1
                return
            }
            directObjects += 1
            guard let key = object.directReferenceKey(using: resolver) else {
                danglingObjects += 1
                return
            }
            guard recordIDs.contains(object.formID.objectID) else {
                danglingObjects += 1
                return
            }
            if sampledKeys.count < Self.sampleLimit {
                sampledKeys.append(key)
            }
        }

        var report: String {
            let versions = render(versions)
            let formats = render(objectFormats)
            let types = render(propertyTypes)
            let carriers = render(carriers)
            let skips = skipped.ranked.map { "\($0.name):\($0.count)" }
                .joined(separator: " ")
            let failures = decodeFailures.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }.joined(separator: " ")
            let samples = sampledKeys.map(\.description).joined(separator: " ")
            return """
            VMAD sweep observed 2026-08-02
            records\t\(records)
            unreadable records\t\(unreadableRecords)
            VMAD fields\t\(vmadFields)
            scripts\t\(scripts)
            properties\t\(properties)
            versions\t\(versions)
            object formats\t\(formats)
            property types\t\(types)
            carriers\t\(carriers)
            QUST fragment sections\t\(questFragmentSections)
            QUST stage fragments\t\(questFragments)
            QUST alias script sections\t\(questAliasScriptSections)
            skipped\t\(skips)
            decode failures\t\(failures)
            direct objects\t\(directObjects)
            null objects\t\(nullObjects)
            dangling objects\t\(danglingObjects)
            sampled ReferenceKeys\t\(samples)

            PEX backing-name probe
            script loads\t\(backing.scriptLoads)
            missing scripts\t\(backing.missingScripts)
            missing properties\t\(backing.missingProperties)
            manual properties\t\(backing.manualProperties)
            automatic properties inspected\t\(backing.inspectedAutomatic)
            conventional ::Property_var names\t\(backing.conventionalNames)
            other backing names\t\(backing.otherNames)
            missing backing names\t\(backing.missingBacking)
            backing names without variables\t\(backing.missingVariable)
            """
        }

        private func render(_ histogram: [some Comparable: Int]) -> String {
            histogram.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }.joined(separator: " ")
        }
    }
}

private struct PexBackingStats {
    var scriptLoads = 0
    var missingScripts = 0
    var missingProperties = 0
    var manualProperties = 0
    var inspectedAutomatic = 0
    var conventionalNames = 0
    var otherNames = 0
    var missingBacking = 0
    var missingVariable = 0
}

private struct PexBackingProbe {
    private enum CacheEntry {
        case object(PexObject)
        case missing
    }

    private let loader: PexScriptLoader
    private var cache: [String: CacheEntry] = [:]
    var stats = PexBackingStats()

    init(root: GameDataRoot) {
        loader = PexScriptLoader(fileSystem: VirtualFileSystem(root: root))
    }

    mutating func inspect(_ scripts: [AttachedScript]) {
        for script in scripts where !script.isRemoved {
            for property in script.properties
                where !property.flags.contains(.removed)
            {
                inspect(property: property.name, on: script.name)
            }
        }
    }

    private mutating func inspect(property name: String, on scriptName: String) {
        guard let resolved = resolve(property: name, on: scriptName) else {
            stats.missingProperties += 1
            return
        }
        guard resolved.property.flags.contains(.automatic) else {
            stats.manualProperties += 1
            return
        }
        stats.inspectedAutomatic += 1
        guard let backing = resolved.property.automaticVariableName else {
            stats.missingBacking += 1
            return
        }
        if PapyrusRuntime.matches(backing, "::\(resolved.property.name)_var") {
            stats.conventionalNames += 1
        } else {
            stats.otherNames += 1
        }
        guard
            resolved.object.variables.contains(where: {
                PapyrusRuntime.matches($0.name, backing)
            })
        else {
            stats.missingVariable += 1
            return
        }
    }

    private mutating func resolve(
        property name: String,
        on scriptName: String
    ) -> (object: PexObject, property: PexProperty)? {
        var currentName = scriptName
        var visited: Set<String> = []
        while !currentName.isEmpty {
            let key = currentName.lowercased()
            guard visited.insert(key).inserted else { return nil }
            guard let object = object(named: currentName) else { return nil }
            if
                let property = object.properties.first(where: {
                    PapyrusRuntime.matches($0.name, name)
                })
            {
                return (object, property)
            }
            currentName = object.parentClassName
        }
        return nil
    }

    private mutating func object(named name: String) -> PexObject? {
        let key = name.lowercased()
        if let cached = cache[key] {
            switch cached {
            case let .object(object): return object
            case .missing: return nil
            }
        }
        do {
            let file = try loader.load(name)
            guard
                let object = file.objects.first(where: {
                    PapyrusRuntime.matches($0.name, name)
                }) ?? file.objects.first
            else {
                cache[key] = .missing
                stats.missingScripts += 1
                return nil
            }
            cache[key] = .object(object)
            stats.scriptLoads += 1
            return object
        } catch {
            cache[key] = .missing
            stats.missingScripts += 1
            return nil
        }
    }
}

extension ScriptDataRealDataTests {
    private var logURL: URL {
        logsDirectory.appending(path: "vmad-sweep.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
    }
}

nonisolated extension ScriptPropertyValue {
    fileprivate var objects: [ScriptObjectReference] {
        switch self {
        case let .object(value): [value]
        case let .objects(values): values
        default: []
        }
    }
}
