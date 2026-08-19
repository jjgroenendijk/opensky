// One install entry point for the headless native families.

import Foundation

nonisolated enum PapyrusNativeFunctions {
    static func install(into registry: inout PapyrusNativeRegistry) {
        installDebug(into: &registry)
        installUtility(into: &registry)
        installMath(into: &registry)
        installDeferredAnimation(into: &registry)
        installObjectReference(into: &registry)
        installUpdateTimers(into: &registry)
        installGlobalVariable(into: &registry)
        installGame(into: &registry)
        installQuest(into: &registry)
        installActor(into: &registry)
        installSpell(into: &registry)
        installPerk(into: &registry)
        installSkill(into: &registry)
    }

    static func failure(
        _ call: PapyrusNativeCall,
        _ detail: String
    ) -> PapyrusNativeResult {
        .failed(.invalidArguments(function: call.qualifiedName, detail: detail))
    }

    static func float(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> Float? {
        guard call.arguments.indices.contains(index) else { return nil }
        return switch call.arguments[index] {
        case let .float(value):
            value
        case let .integer(value):
            Float(value)
        default:
            nil
        }
    }

    static func integer(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> Int32? {
        guard call.arguments.indices.contains(index) else { return nil }
        guard case let .integer(value) = call.arguments[index] else { return nil }
        return value
    }

    static func string(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> String? {
        guard call.arguments.indices.contains(index) else { return nil }
        guard case let .string(value) = call.arguments[index] else { return nil }
        return value
    }
}
