// Which Papyrus events the scripts handle, by scripts, and which ones the engine sends.
// An event is an `On...` function an engine class declares: a script with natives,
// such as `ObjectReference`. A handler is the same name in a script without natives.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsPEX

nonisolated public struct PapyrusEventCensus: Equatable, Sendable {
    /// Event name, as the engine class spells it -> scripts that handle it.
    public private(set) var handlers = GapCounts()
    public private(set) var declaredEventCount = 0

    public init(files: [PexFile]) {
        let objects = files.flatMap(\.objects)
        let engineClasses = objects.filter { object in
            object.functions.contains { $0.flags.contains(.native) }
        }
        var declared: [String: String] = [:]
        for object in engineClasses {
            for function in Self.namedFunctions(object) where Self.isEventName(function.name) {
                if !function.function.flags.contains(.native) {
                    declared[function.name.lowercased()] = function.name
                }
            }
        }
        declaredEventCount = declared.count
        let engineNames = Set(engineClasses.map { $0.name.lowercased() })
        for object in objects where !engineNames.contains(object.name.lowercased()) {
            let handled = Set(Self.namedFunctions(object).compactMap {
                declared[$0.name.lowercased()]
            })
            for name in handled {
                handlers.add(name)
            }
        }
    }

    public static func isSent(_ event: String) -> Bool {
        PapyrusEngineEvents.sent.contains(event.lowercased())
    }

    private static func namedFunctions(_ object: PexObject) -> [PexNamedFunction] {
        object.states.flatMap(\.functions)
    }

    private static func isEventName(_ name: String) -> Bool {
        let characters = Array(name)
        return characters.count > 2 && name.hasPrefix("On") && characters[2].isUppercase
    }
}
