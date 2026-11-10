// Deterministic iteration order for the stores built over `RecordIndex`.
//
// `RecordIndex.records` is a dictionary, so a store that folds it into an
// editor-ID map needs an explicit order or the winner of an editor-ID
// collision changes between runs. Lowest plugin priority first, so the last
// write into such a map is the definition the load order prefers.

import Foundation
import OpenSkyFormatsESM

nonisolated extension RecordIndex {
    func precedes(_ left: ResolvedFormID, _ right: ResolvedFormID) -> Bool {
        let leftSource = records[left]?.sourcePlugin ?? left.plugin
        let rightSource = records[right]?.sourcePlugin ?? right.plugin
        let leftPriority = priority(ofPlugin: leftSource)
        let rightPriority = priority(ofPlugin: rightSource)
        if leftPriority != rightPriority {
            return leftPriority < rightPriority
        }
        if left.plugin.caseInsensitiveCompare(right.plugin) != .orderedSame {
            return left.plugin.localizedCaseInsensitiveCompare(right.plugin) == .orderedAscending
        }
        return left.objectID < right.objectID
    }
}
