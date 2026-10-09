// `FormList` reads over the load-order FLST data. A list a script edits at runtime
// (`AddForm`, `Revert`) is not modelled, so these read the plugin entries.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// `int GetSize()` and `Form GetAt(int)`. A nested list counts as one entry, as the
    /// list stores it.
    public static func installFormList(into registry: inout PapyrusNativeRegistry) {
        formList("GetSize", into: &registry) { _, entries, _ in
            .returned(.integer(Int32(clamping: entries.count)))
        }
        formList("GetAt", into: &registry) { call, entries, world in
            guard let index = integer(call, at: 0) else {
                return failure(call, "GetAt needs an int")
            }
            guard
                entries.indices.contains(Int(index)),
                let key = entries[Int(index)],
                let handle = world.objectHandle(for: key)
            else { return .returned(.none) }
            return .returned(.object(handle))
        }
    }

    private static func formList(
        _ functionName: String,
        into registry: inout PapyrusNativeRegistry,
        body: @escaping @MainActor (
            PapyrusNativeCall, [ReferenceKey?], any PapyrusWorldBridge
        ) -> PapyrusNativeResult
    ) {
        registry.register(PapyrusNativeFunction(
            scriptName: "FormList",
            functionName: functionName
        ) { call, context in
            guard let target = worldTarget(call, context) else {
                return needsWorld(call)
            }
            guard let entries = target.world.formListEntries(of: target.key) else {
                return failure(call, "\(functionName) needs FLST data and a form list receiver")
            }
            return body(call, entries, target.world)
        })
    }
}
