// Record-data reads for the form natives: form-list entries and `KWDA` keywords.

import OpenSkyFormatsESM
import OpenSkyGameData

extension PapyrusWorldStateBridge {
    func pluginFormListEntries(of key: ReferenceKey) -> [ReferenceKey?]? {
        guard
            let formListStore,
            case let .plugin(plugin, objectID) = key,
            let resolved = formListStore.formList(ResolvedFormID(
                plugin: plugin,
                objectID: objectID
            ))
        else { return nil }
        return resolved.list.entries.map { entry in
            entry
                .flatMap { formListStore.resolvedID($0, fromPlugin: resolved.sourcePlugin) }
                .map(ReferenceKey.init(resolved:))
        }
    }

    /// The base form of a placed reference, read in its plugin's space.
    func resolvedBase(of reference: ReferenceKey) -> ReferenceKey? {
        guard let keywordStore, let base = baseObject(of: reference) else { return nil }
        let space = if case let .plugin(plugin, _) = reference {
            plugin
        } else {
            FormIDResolver.loadOrderSpaceName
        }
        return keywordStore.resolvedID(base, fromPlugin: space).map(ReferenceKey.init(resolved:))
    }

    public func formHasKeyword(_ form: ReferenceKey, keyword: ReferenceKey) -> Bool? {
        guard
            let keywordStore,
            let base = keywordedForm(form, in: keywordStore),
            case let .plugin(keywordPlugin, keywordID) = keyword
        else { return nil }
        return keywordStore.hasKeyword(
            ResolvedFormID(plugin: keywordPlugin, objectID: keywordID), on: base
        )
    }

    /// A placed reference's base, read in its plugin's space as `HasKeyword`
    /// conditions read it; a generated one's base is in load-order space.
    private func keywordedForm(_ form: ReferenceKey, in store: KeywordStore) -> ResolvedFormID? {
        guard let base = baseObject(of: form) else {
            guard case let .plugin(plugin, objectID) = form else { return nil }
            return ResolvedFormID(plugin: plugin, objectID: objectID)
        }
        let space = if case let .plugin(plugin, _) = form {
            plugin
        } else {
            FormIDResolver.loadOrderSpaceName
        }
        return store.resolvedID(base, fromPlugin: space)
    }
}
