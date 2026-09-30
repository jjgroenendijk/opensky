// Env-gated signature check for the faction and relationship natives against
// the compiled `Actor.pex` and `Faction.pex` the install ships. A wrong
// argument count breaks mods, and the shipped script cannot drift from the
// game. Example: `Actor.AddToFaction` is a Papyrus wrapper, not a native; its
// body is `if !IsInFaction(akFaction); SetFactionRank(akFaction, 0); endIf`.

import Foundation
@testable import OpenSkyFormatsPEX
@testable import OpenSkyGameData
@testable import OpenSkyScripting
import Testing

struct PapyrusNativeSignatureRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    /// One expectation: the script, the function, how many arguments the
    /// engine's registration reads, and whether the shipped declaration carries
    /// the `native` flag.
    private struct Expected {
        let script: String
        let function: String
        let parameters: Int
        let isNative: Bool

        init(_ script: String, _ function: String, _ parameters: Int, isNative: Bool = true) {
            self.script = script
            self.function = function
            self.parameters = parameters
            self.isNative = isNative
        }
    }

    /// Every function `PapyrusNativeFaction.swift` installs, with the argument
    /// count its body reads. `isNative` records the shipped script. Only
    /// `AddToFaction` is false; OpenSky registers it anyway with the wrapper's
    /// semantics, so it works without the game's script.
    private static let installed = [
        Expected("Actor", "AddToFaction", 1, isNative: false),
        Expected("Actor", "RemoveFromFaction", 1),
        Expected("Actor", "IsInFaction", 1),
        Expected("Actor", "GetFactionRank", 1),
        Expected("Actor", "SetFactionRank", 2),
        Expected("Actor", "GetRelationshipRank", 1),
        Expected("Actor", "SetRelationshipRank", 2),
        Expected("Actor", "GetFactionReaction", 1),
        Expected("Actor", "IsHostileToActor", 1),
        Expected("Faction", "GetReaction", 1)
    ]

    /// Functions this family deliberately leaves unregistered. Their absence
    /// from the registry is asserted, and the signature the install declares for
    /// each is reported, so the next implementation starts from an observation
    /// rather than from a guess.
    private static let unregistered = [
        Expected("Actor", "ModFactionRank", 2),
        Expected("Faction", "SetReaction", 2),
        Expected("Faction", "ModReaction", 2)
    ]

    @Test(.enabled(if: Self.dataRoot != nil))
    func everyInstalledFactionNativeMatchesTheShippedDeclaration() throws {
        let root = try #require(Self.dataRoot)
        let loader = PexScriptLoader(fileSystem: VirtualFileSystem(root: root))
        var declarations: [String: [String: PexFunction]] = [:]
        for script in Set((Self.installed + Self.unregistered).map(\.script)) {
            declarations[script] = try Self.functions(in: loader.load(script))
        }

        var lines: [String] = []
        for expected in Self.installed {
            let function = try #require(
                declarations[expected.script]?[expected.function.lowercased()],
                "\(expected.script).\(expected.function) is not declared by the install"
            )
            #expect(
                function.flags.contains(.native) == expected.isNative,
                "\(expected.script).\(expected.function) changed native-ness"
            )
            let arity = "\(expected.script).\(expected.function) takes "
                + "\(function.parameters.count) arguments, not \(expected.parameters)"
            #expect(function.parameters.count == expected.parameters, Comment(rawValue: arity))
            lines.append(Self.describe(expected, function))
        }

        let registry = PapyrusNativeRegistry.standard(context: PapyrusNativeContext())
        for expected in Self.unregistered {
            let stale = "\(expected.script).\(expected.function) is registered now — "
                + "move it out of the unregistered list"
            #expect(
                !registry.contains(
                    scriptName: expected.script, functionName: expected.function
                ),
                Comment(rawValue: stale)
            )
            guard
                let declared = declarations[expected.script]?[expected.function.lowercased()]
            else { continue }
            lines.append("  [unregistered]" + Self.describe(expected, declared))
        }

        print(
            ([
                "[INFO] faction and relationship native signatures, "
                    + "from the install's own compiled scripts:"
            ] + lines).joined(separator: "\n")
        )
    }

    private static func describe(_ expected: Expected, _ function: PexFunction) -> String {
        "  \(expected.script).\(expected.function): returns \(function.returnTypeName), "
            + "takes \(function.parameters.map(\.typeName).joined(separator: ", ")), "
            + "native \(function.flags.contains(.native))"
    }

    /// Every function one script declares, keyed by lowercased name. Papyrus is
    /// case-insensitive, and the registry keys the same way.
    private static func functions(in file: PexFile) throws -> [String: PexFunction] {
        var functions: [String: PexFunction] = [:]
        for object in file.objects {
            for state in object.states {
                for named in state.functions {
                    functions[named.name.lowercased()] = named.function
                }
            }
        }
        return functions
    }
}
