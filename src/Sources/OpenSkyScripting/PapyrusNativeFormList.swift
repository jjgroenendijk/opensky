// `FormList` reads over the load-order FLST data. A list a script edits at runtime
// (`AddForm`, `Revert`) is not modelled, so these read the plugin entries.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    /// `int GetSize()`, `Form GetAt(int)`, `int Find(Form)`, `bool HasForm(Form)`, and
    /// `bool Form.HasKeyword(Keyword)`. A nested list counts as one entry, as the list
    /// stores it, so `Find` does not look inside it.
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
        formList("Find", into: &registry) { call, entries, world in
            let index = formListIndex(call, entries, world)
            return .returned(.integer(index.map { Int32(clamping: $0) } ?? -1))
        }
        formList("HasForm", into: &registry) { call, entries, world in
            .returned(.boolean(formListIndex(call, entries, world) != nil))
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

    /// The first index of the form argument 0 names, or nil when it is not listed.
    private static func formListIndex(
        _ call: PapyrusNativeCall,
        _ entries: [ReferenceKey?],
        _ world: any PapyrusWorldBridge
    ) -> Int? {
        guard
            let handle = objectArgument(call, at: 0),
            let form = world.referenceKey(for: handle)
        else { return nil }
        return entries.firstIndex { $0?.namingPlayer == form.namingPlayer }
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
