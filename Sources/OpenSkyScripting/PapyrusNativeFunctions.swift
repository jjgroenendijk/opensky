// One install entry point for the headless native families.

import Foundation
import OpenSkyScriptingInterface

public enum PapyrusNativeFunctions {
    public static func install(into registry: inout PapyrusNativeRegistry) {
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
        installLevel(into: &registry)
        installCrime(into: &registry)
        installGuard(into: &registry)
        installBarter(into: &registry)
        installFaction(into: &registry)
        installLock(into: &registry)
        installTrap(into: &registry)
        installFormList(into: &registry)
        installStory(into: &registry)
        installPresentation(into: &registry)
        installMenus(into: &registry)
        installReferenceAlias(into: &registry)
        installVehicle(into: &registry)
    }

    public static func failure(
        _ call: PapyrusNativeCall,
        _ detail: String
    ) -> PapyrusNativeResult {
        .failed(.invalidArguments(function: call.qualifiedName, detail: detail))
    }

    public static func float(
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

    public static func integer(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> Int32? {
        guard call.arguments.indices.contains(index) else { return nil }
        guard case let .integer(value) = call.arguments[index] else { return nil }
        return value
    }

    /// An optional Bool argument, `fallback` when the call left it off. An
    /// integer reads as its truth value, which is what the compiler's implicit
    /// cast of an int literal produces.
    public static func boolean(
        _ call: PapyrusNativeCall,
        at index: Int,
        default fallback: Bool
    ) -> Bool {
        guard call.arguments.indices.contains(index) else { return fallback }
        return switch call.arguments[index] {
        case let .boolean(value): value
        case let .integer(value): value != 0
        default: fallback
        }
    }

    public static func string(
        _ call: PapyrusNativeCall,
        at index: Int
    ) -> String? {
        guard call.arguments.indices.contains(index) else { return nil }
        guard case let .string(value) = call.arguments[index] else { return nil }
        return value
    }
}
