// `FormList` reads over the load-order FLST data. A list a script edits at runtime
// (`AddForm`, `Revert`) is not modelled, so these read the plugin entries.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// `int GetSize()`, `Form GetAt(int)`, and `bool Form.HasKeyword(Keyword)`. A nested
    /// list counts as one entry, as the list stores it.
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
        // <https://ck.uesp.net/wiki/HasKeyword_-_Form>. A placed reference reads its base.
        registry.register(PapyrusNativeFunction(
            scriptName: "Form", functionName: "HasKeyword"
        ) { call, context in
            guard let target = worldTarget(call, context) else { return needsWorld(call) }
            guard
                let handle = objectArgument(call, at: 0),
                let keyword = target.world.referenceKey(for: handle)
            else { return .returned(.boolean(false)) }
            guard let answer = target.world.formHasKeyword(target.key, keyword: keyword) else {
                return failure(call, "HasKeyword needs keyword data")
            }
            return .returned(.boolean(answer))
        })
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
