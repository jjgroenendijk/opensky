// Load-order-wide COBJ lookup above RecordIndex, indexed by workbench keyword
// and by created object, so a station and an item can both list their recipes.
// Links resolve relative to the plugin that authored the recipe.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM

nonisolated public struct ResolvedRecipe: Equatable, Sendable {
    /// One CNTO with its item resolved. `item` is nil when the load order lacks it.
    public struct Component: Equatable, Sendable {
        public let item: ResolvedFormID?
        public let count: Int32
    }

    public let id: ResolvedFormID
    public let recipe: ConstructibleObject
    public let sourcePlugin: String
    public let createdObject: ResolvedFormID?
    public let workbenchKeyword: ResolvedFormID?
    public let components: [Component]
}

nonisolated public struct RecipeStore: Sendable {
    private let table: ResolvedRecordTable<ResolvedRecipe>
    private let idsByWorkbenchKeyword: [ResolvedFormID: [ResolvedFormID]]
    private let idsByCreatedObject: [ResolvedFormID: [ResolvedFormID]]

    public var recipes: [ResolvedFormID: ResolvedRecipe] {
        table.values
    }

    public var skippedRecords: SkippedRecords {
        table.skipped
    }

    public init(index: RecordIndex) {
        let table = ResolvedRecordTable(
            index: index,
            types: ["COBJ"],
            decode: { try ConstructibleObject(record: $0.record) },
            editorID: \.editorID,
            resolve: { id, recipe, sourcePlugin in
                ResolvedRecipe(
                    id: id,
                    recipe: recipe,
                    sourcePlugin: sourcePlugin,
                    createdObject: index.resolvedID(recipe.createdObject, fromPlugin: sourcePlugin),
                    workbenchKeyword: index.resolvedID(
                        recipe.workbenchKeyword, fromPlugin: sourcePlugin
                    ),
                    components: recipe.components.map {
                        ResolvedRecipe.Component(
                            item: index.resolvedID($0.item, fromPlugin: sourcePlugin),
                            count: $0.count
                        )
                    }
                )
            }
        )
        self.table = table
        var byKeyword: [ResolvedFormID: [ResolvedFormID]] = [:]
        var byCreated: [ResolvedFormID: [ResolvedFormID]] = [:]
        for recipe in table.orderedValues {
            if let keyword = recipe.workbenchKeyword {
                byKeyword[keyword, default: []].append(recipe.id)
            }
            if let created = recipe.createdObject {
                byCreated[created, default: []].append(recipe.id)
            }
        }
        idsByWorkbenchKeyword = byKeyword
        idsByCreatedObject = byCreated
    }

    public init(plugins: [(name: String, file: ESMFile)]) {
        self.init(index: RecordIndex(plugins: plugins, recordTypes: ["COBJ"]))
    }

    public func recipe(_ id: ResolvedFormID) -> ResolvedRecipe? {
        table.value(id)
    }

    public func recipe(editorID: String) -> ResolvedRecipe? {
        table.value(editorID: editorID)
    }

    /// Recipes a station with this KYWD offers, in load order.
    public func recipes(workbenchKeyword keyword: ResolvedFormID) -> [ResolvedRecipe] {
        idsByWorkbenchKeyword[keyword, default: []].compactMap { table.value($0) }
    }

    /// Recipes that make this item, in load order.
    public func recipes(creating object: ResolvedFormID) -> [ResolvedRecipe] {
        idsByCreatedObject[object, default: []].compactMap { table.value($0) }
    }
}
